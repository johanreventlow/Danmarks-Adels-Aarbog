import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  // Review 37 C11: mobilen trækker React 19 ind i rodens node_modules; web skal altid bundte sin egen React 18.
  resolve: { dedupe: ['react', 'react-dom'] },
});
