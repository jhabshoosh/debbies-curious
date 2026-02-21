import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useTTS } from "../useTTS";

const mockSpeak = vi.fn();
const mockCancel = vi.fn();

beforeEach(() => {
  vi.stubGlobal("speechSynthesis", {
    speak: mockSpeak,
    cancel: mockCancel,
  });
  vi.stubGlobal(
    "SpeechSynthesisUtterance",
    class MockUtterance {
      text = "";
      rate = 1;
      pitch = 1;
      onstart: (() => void) | null = null;
      onend: (() => void) | null = null;
      onerror: (() => void) | null = null;
      constructor(text: string) {
        this.text = text;
      }
    }
  );
  localStorage.clear();
  mockSpeak.mockReset();
  mockCancel.mockReset();
});

describe("useTTS", () => {
  it("defaults to supported when speechSynthesis exists", () => {
    const { result } = renderHook(() => useTTS());
    expect(result.current.supported).toBe(true);
  });

  it("defaults autoRead to true", () => {
    const { result } = renderHook(() => useTTS());
    expect(result.current.autoRead).toBe(true);
  });

  it("toggles autoRead and persists to localStorage", () => {
    const { result } = renderHook(() => useTTS());

    act(() => {
      result.current.toggleAutoRead();
    });

    expect(result.current.autoRead).toBe(false);
    expect(localStorage.getItem("debbies-curious-tts-auto")).toBe("false");

    act(() => {
      result.current.toggleAutoRead();
    });

    expect(result.current.autoRead).toBe(true);
    expect(localStorage.getItem("debbies-curious-tts-auto")).toBe("true");
  });

  it("reads autoRead preference from localStorage", () => {
    localStorage.setItem("debbies-curious-tts-auto", "false");
    const { result } = renderHook(() => useTTS());
    expect(result.current.autoRead).toBe(false);
  });

  it("calls speechSynthesis.speak when speak is called", () => {
    const { result } = renderHook(() => useTTS());

    act(() => {
      result.current.speak("Hello world");
    });

    expect(mockCancel).toHaveBeenCalled();
    expect(mockSpeak).toHaveBeenCalled();
  });

  it("calls speechSynthesis.cancel when stop is called", () => {
    const { result } = renderHook(() => useTTS());

    act(() => {
      result.current.stop();
    });

    expect(mockCancel).toHaveBeenCalled();
  });
});
