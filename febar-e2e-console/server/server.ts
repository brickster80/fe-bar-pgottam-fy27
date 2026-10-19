import { createApp, analytics, genie, lakebase, server } from '@databricks/appkit';
import { setupE2eRoutes } from './routes/e2e-routes';

createApp({
  plugins: [
    analytics(),
    // "Authorized Access, Unauthorized Movement" Genie space, registered under the `e2e` alias
    // (must match <GenieChat alias="e2e"> on the client).
    genie({ spaces: { e2e: process.env.DATABRICKS_GENIE_SPACE_ID ?? '' } }),
    lakebase(),
    server(),
  ],
  async onPluginsReady(appkit) {
    await setupE2eRoutes(appkit);
  },
}).catch(console.error);
