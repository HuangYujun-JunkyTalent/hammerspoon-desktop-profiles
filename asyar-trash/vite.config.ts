import { defineExtensionConfig } from 'asyar-sdk/vite';
import { fileURLToPath, URL } from 'url';

// The SDK finds worker.html and sets the build policy that a worker needs.
export default defineExtensionConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
});
