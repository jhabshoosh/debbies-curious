import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { TTSControls } from "../TTSControls";

const defaultProps = {
  autoRead: true,
  isSpeaking: false,
  supported: true,
  onToggleAutoRead: vi.fn(),
  onSpeak: vi.fn(),
  onStop: vi.fn(),
  hasFact: false,
};

describe("TTSControls", () => {
  it("renders auto-read toggle", () => {
    render(<TTSControls {...defaultProps} />);
    expect(screen.getByText("Auto-read")).toBeInTheDocument();
    expect(screen.getByRole("checkbox")).toBeChecked();
  });

  it("does not render when not supported", () => {
    const { container } = render(
      <TTSControls {...defaultProps} supported={false} />
    );
    expect(container.innerHTML).toBe("");
  });

  it("toggles auto-read on click", async () => {
    const user = userEvent.setup();
    const onToggle = vi.fn();
    render(<TTSControls {...defaultProps} onToggleAutoRead={onToggle} />);

    await user.click(screen.getByRole("checkbox"));
    expect(onToggle).toHaveBeenCalledOnce();
  });

  it("shows Read Aloud button when fact exists", () => {
    render(<TTSControls {...defaultProps} hasFact={true} />);
    expect(
      screen.getByRole("button", { name: /read aloud/i })
    ).toBeInTheDocument();
  });

  it("does not show Read Aloud button when no fact", () => {
    render(<TTSControls {...defaultProps} hasFact={false} />);
    expect(
      screen.queryByRole("button", { name: /read aloud/i })
    ).not.toBeInTheDocument();
  });

  it("shows Stop button when speaking", () => {
    render(<TTSControls {...defaultProps} hasFact={true} isSpeaking={true} />);
    expect(
      screen.getByRole("button", { name: /stop reading/i })
    ).toBeInTheDocument();
  });

  it("calls onSpeak when Read Aloud is clicked", async () => {
    const user = userEvent.setup();
    const onSpeak = vi.fn();
    render(<TTSControls {...defaultProps} hasFact={true} onSpeak={onSpeak} />);

    await user.click(screen.getByRole("button", { name: /read aloud/i }));
    expect(onSpeak).toHaveBeenCalledOnce();
  });

  it("calls onStop when Stop is clicked", async () => {
    const user = userEvent.setup();
    const onStop = vi.fn();
    render(
      <TTSControls
        {...defaultProps}
        hasFact={true}
        isSpeaking={true}
        onStop={onStop}
      />
    );

    await user.click(screen.getByRole("button", { name: /stop reading/i }));
    expect(onStop).toHaveBeenCalledOnce();
  });
});
