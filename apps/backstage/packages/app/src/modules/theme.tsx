import { ThemeBlueprint } from '@backstage/plugin-app-react';
import {
  UnifiedThemeProvider,
  createUnifiedTheme,
  genPageTheme,
  palettes,
} from '@backstage/theme';

const portalLightTheme = createUnifiedTheme({
  palette: {
    ...palettes.light,
    primary: {
      main: '#006d77',
    },
    secondary: {
      main: '#2f5d62',
    },
    navigation: {
      background: '#102a2d',
      indicator: '#7df3e1',
      color: '#d8f3f0',
      selectedColor: '#ffffff',
      navItem: {
        hoverBackground: '#173b40',
      },
    },
  },
  defaultPageTheme: 'home',
  pageTheme: {
    home: genPageTheme({
      colors: ['#102a2d', '#006d77'],
      shape: 'wave',
    }),
    service: genPageTheme({
      colors: ['#334155', '#006d77'],
      shape: 'round',
    }),
    tool: genPageTheme({
      colors: ['#2f5d62', '#006d77'],
      shape: 'wave2',
    }),
    documentation: genPageTheme({
      colors: ['#1f2937', '#475569'],
      shape: 'wave',
    }),
  },
  fontFamily:
    '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
});

export const portalTheme = ThemeBlueprint.make({
  params: {
    theme: {
      id: 'portal',
      title: 'Portal',
      variant: 'light',
      Provider: ({ children }) => (
        <UnifiedThemeProvider theme={portalLightTheme} themeName="portal">
          {children}
        </UnifiedThemeProvider>
      ),
    },
  },
});
