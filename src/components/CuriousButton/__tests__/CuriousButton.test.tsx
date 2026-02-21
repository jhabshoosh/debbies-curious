import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CuriousButton } from "../CuriousButton";

describe("CuriousButton", () => {
  it("renders with 'I'm Curious!' text in idle state", () => {
    render(<CuriousButton status="idle" onClick={vi.fn()} />);
    expect(screen.getByRole("button")).toHaveTextContent("I'm Curious!");
  });

  it("shows 'Finding you...' when locating", () => {
    render(<CuriousButton status="locating" onClick={vi.fn()} />);
    expect(screen.getByRole("button")).toHaveTextContent("Finding you...");
  });

  it("shows 'Thinking...' when thinking", () => {
    render(<CuriousButton status="thinking" onClick={vi.fn()} />);
    expect(screen.getByRole("button")).toHaveTextContent("Thinking...");
  });

  it("shows 'Try Again' on error", () => {
    render(<CuriousButton status="error" onClick={vi.fn()} />);
    expect(screen.getByRole("button")).toHaveTextContent("Try Again");
  });

  it("is disabled during loading states", () => {
    const { rerender } = render(
      <CuriousButton status="locating" onClick={vi.fn()} />
    );
    expect(screen.getByRole("button")).toBeDisabled();

    rerender(<CuriousButton status="thinking" onClick={vi.fn()} />);
    expect(screen.getByRole("button")).toBeDisabled();
  });

  it("is enabled in idle, done, and error states", () => {
    const { rerender } = render(
      <CuriousButton status="idle" onClick={vi.fn()} />
    );
    expect(screen.getByRole("button")).toBeEnabled();

    rerender(<CuriousButton status="done" onClick={vi.fn()} />);
    expect(screen.getByRole("button")).toBeEnabled();

    rerender(<CuriousButton status="error" onClick={vi.fn()} />);
    expect(screen.getByRole("button")).toBeEnabled();
  });

  it("calls onClick when clicked", async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(<CuriousButton status="idle" onClick={onClick} />);

    await user.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledOnce();
  });

  it("has aria-busy during loading", () => {
    render(<CuriousButton status="locating" onClick={vi.fn()} />);
    expect(screen.getByRole("button")).toHaveAttribute("aria-busy", "true");
  });
});
