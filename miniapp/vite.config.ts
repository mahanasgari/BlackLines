import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "node:path";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: "/shop/",
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    port: 5179,
    proxy: {
      "/shop/api": "http://127.0.0.1:8105",
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
