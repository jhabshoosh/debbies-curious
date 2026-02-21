import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { TellMeMoreButton } from "../TellMeMoreButton";

describe("TellMeMoreButton", () => {
  it("renders with 'Tell Me More!' text", () => {
    render(<TellMeMoreButton onClick={vi.fn()} loading={false} />);
    expect(screen.getByRole("button")).toHaveTextContent("Tell Me More!");
  });

  it("shows 'Thinking...' when loading", () => {
    render(<TellMeMoreButton onClick={vi.fn()} loading={true} />);
    expect(screen.getByRole("button")).toHaveTextContent("Thinking...");
  });

  it("is disabled when loading", () => {
    render(<TellMeMoreButton onClick={vi.fn()} loading={true} />);
    expect(screen.getByRole("button")).toBeDisabled();
  });

  it("is enabled when not loading", () => {
    render(<TellMeMoreButton onClick={vi.fn()} loading={false} />);
    expect(screen.getByRole("button")).toBeEnabled();
  });

  it("calls onClick when clicked", async () => {
    const user = userEvent.setup();
    const onClick = vi.fn();
    render(<TellMeMoreButton onClick={onClick} loading={false} />);

    await user.click(screen.getByRole("button"));
    expect(onClick).toHaveBeenCalledOnce();
  });

  it("has aria-busy when loading", () => {
    render(<TellMeMoreButton onClick={vi.fn()} loading={true} />);
    expect(screen.getByRole("button")).toHaveAttribute("aria-busy", "true");
  });
});
