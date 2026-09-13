import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { installAutoHideScrollbars } from "./autoHideScrollbars";
import "./style.css";

const removeScrollbarBehavior = installAutoHideScrollbars();
if (import.meta.hot) import.meta.hot.dispose(removeScrollbarBehavior);

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
