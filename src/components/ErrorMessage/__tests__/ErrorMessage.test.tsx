import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { ErrorMessage } from "../ErrorMessage";

describe("ErrorMessage", () => {
  it("renders the error message", () => {
    render(<ErrorMessage message="Location access denied." />);
    expect(screen.getByText("Location access denied.")).toBeInTheDocument();
  });

  it("has role=alert for a11y", () => {
    render(<ErrorMessage message="Something went wrong." />);
    expect(screen.getByRole("alert")).toBeInTheDocument();
  });
});
