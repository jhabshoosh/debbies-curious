import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { FactDisplay } from "../FactDisplay";

describe("FactDisplay", () => {
  it("renders the fact text", () => {
    render(<FactDisplay fact="The Eiffel Tower was built in 1889." />);
    expect(
      screen.getByText("The Eiffel Tower was built in 1889.")
    ).toBeInTheDocument();
  });

  it("has role=status for a11y", () => {
    render(<FactDisplay fact="A fact" />);
    expect(screen.getByRole("status")).toBeInTheDocument();
  });

  it("has aria-live=polite for screen readers", () => {
    render(<FactDisplay fact="A fact" />);
    expect(screen.getByRole("status")).toHaveAttribute("aria-live", "polite");
  });
});
