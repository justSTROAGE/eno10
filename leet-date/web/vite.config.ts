import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    proxy: {
      // Both /api and /pay are proxied through nginx (host port 6789) so we
      // don't need to expose leetdate:8000 or payments:7000 separately on the
      // host. nginx handles the routing to the right container.
      //
      // changeOrigin: false (default) is required — otherwise vite rewrites
      // the Host header to localhost:6789, and Bottle's absolute redirects
      // would punt the popup off this origin, breaking the postMessage flow.
      "/api": {
        target: "http://localhost:6789",
        ws: true,
      },
      "/pay": {
        target: "http://localhost:6789",
      },
    },
  },
});
