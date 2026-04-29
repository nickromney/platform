import { SignInPage } from '@backstage/core-components';
import { createApp } from '@backstage/frontend-defaults';
import { createFrontendModule } from '@backstage/frontend-plugin-api';
import apiDocsPlugin from '@backstage/plugin-api-docs/alpha';
import { SignInPageBlueprint } from '@backstage/plugin-app-react';
import catalogPlugin from '@backstage/plugin-catalog/alpha';
import { navModule } from './modules/nav';

const signInPage = SignInPageBlueprint.make({
  params: {
    loader: async () => props => <SignInPage {...props} providers={['guest']} />,
  },
});

export default createApp({
  features: [
    catalogPlugin,
    apiDocsPlugin,
    navModule,
    createFrontendModule({
      pluginId: 'app',
      extensions: [signInPage],
    }),
  ],
});
