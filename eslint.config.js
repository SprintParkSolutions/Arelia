import js from "@eslint/js";
import lwc from "@lwc/eslint-plugin-lwc";
import aura from "@salesforce/eslint-plugin-aura";
import lightning from "@salesforce/eslint-plugin-lightning";
import importPlugin from "eslint-plugin-import";
import jest from "eslint-plugin-jest";

export default [
  js.configs.recommended,

  {
    files: ["force-app/main/default/{lwc,aura}/**/*.js"],

    plugins: {
      "@lwc/lwc": lwc,
      "@salesforce/aura": aura,
      "@salesforce/lightning": lightning,
      import: importPlugin,
      jest: jest
    },

    languageOptions: {
      ecmaVersion: 2023,
      sourceType: "module",
      globals: {
        window: "readonly",
        document: "readonly",
        console: "readonly",
        CustomEvent: "readonly",
        Promise: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly"
      }
    },

    rules: {
      "no-console": ["error", { allow: ["warn", "error"] }],
      "no-debugger": "error",
      "no-unused-vars": "warn",
      "no-undef": "error",
      "eqeqeq": ["error", "always"],
      "curly": "error",
      "semi": ["error", "always"],

      "@lwc/lwc/no-async-await-in-wire": "error",
      "@lwc/lwc/no-deprecated": "warn",
      "@lwc/lwc/no-inner-html": "error",
      "@lwc/lwc/no-dupe-class-members": "error"
    }
  },

  {
    ignores: [
      "node_modules/**",
      ".sfdx/**",
      ".sf/**",
      "coverage/**",
      "test-results/**",
      "scan-results/**",
      "apex-pmd-report.*",
      "lwc-eslint-report.*"
    ]
  }
];
