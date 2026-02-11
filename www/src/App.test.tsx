import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import App from "./App";

describe("App", () => {
  it("renders starter landing page", () => {
    render(<App />);
    expect(screen.getByText("FsharpStarter")).toBeInTheDocument();
  });
});
