import { createBackendModule } from '@backstage/backend-plugin-api';
import {
  createTemplateAction,
  scaffolderActionsExtensionPoint,
} from '@backstage/plugin-scaffolder-node';
import { readdir, readFile, stat } from 'node:fs/promises';
import { relative, resolve, sep } from 'node:path';

type GiteaPublishInput = {
  repoName: string;
  owner?: string;
  description?: string;
  sourcePath?: string;
  defaultBranch?: string;
  private?: boolean;
};

type GiteaRequestOptions = {
  method?: string;
  body?: unknown;
  allowStatuses?: number[];
};

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required for gitea:repo:publish`);
  }
  return value;
}

function boolEnv(name: string, defaultValue: boolean): boolean {
  const value = process.env[name]?.trim().toLowerCase();
  if (!value) {
    return defaultValue;
  }
  return ['1', 'true', 'yes', 'y'].includes(value);
}

function authHeader(): string {
  const token = process.env.GITEA_TOKEN?.trim();
  if (token) {
    return `token ${token}`;
  }

  const username = requiredEnv('GITEA_USERNAME');
  const password = requiredEnv('GITEA_PASSWORD');
  return `Basic ${Buffer.from(`${username}:${password}`).toString('base64')}`;
}

function encodedPath(path: string): string {
  return path.split('/').map(encodeURIComponent).join('/');
}

function isWithin(parent: string, child: string): boolean {
  return child === parent || child.startsWith(`${parent}${sep}`);
}

async function listFiles(root: string, current = root): Promise<string[]> {
  const entries = await readdir(current);
  const files: string[] = [];

  for (const entry of entries) {
    if (entry === '.git') {
      continue;
    }

    const absolute = resolve(current, entry);
    const details = await stat(absolute);
    if (details.isDirectory()) {
      files.push(...(await listFiles(root, absolute)));
    } else if (details.isFile()) {
      files.push(relative(root, absolute).replaceAll(sep, '/'));
    }
  }

  return files.sort();
}

async function giteaRequest<T>(
  baseUrl: string,
  path: string,
  options: GiteaRequestOptions = {},
): Promise<{ status: number; body: T | undefined }> {
  const response = await fetch(`${baseUrl}${path}`, {
    method: options.method ?? 'GET',
    headers: {
      authorization: authHeader(),
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  const allowStatuses = options.allowStatuses ?? [200, 201, 202, 204];
  const text = await response.text();
  const parsed = text ? (JSON.parse(text) as T) : undefined;

  if (!allowStatuses.includes(response.status)) {
    throw new Error(
      `Gitea API ${options.method ?? 'GET'} ${path} returned ${response.status}: ${text}`,
    );
  }

  return { status: response.status, body: parsed };
}

async function ensureOrg(baseUrl: string, owner: string): Promise<void> {
  const current = await giteaRequest(baseUrl, `/api/v1/orgs/${owner}`, {
    allowStatuses: [200, 404],
  });

  if (current.status === 200) {
    return;
  }

  await giteaRequest(baseUrl, '/api/v1/orgs', {
    method: 'POST',
    allowStatuses: [201, 409, 422],
    body: { username: owner },
  });
}

async function ensureRepo(
  baseUrl: string,
  owner: string,
  input: GiteaPublishInput,
  ownerIsOrg: boolean,
): Promise<void> {
  const existing = await giteaRequest(
    baseUrl,
    `/api/v1/repos/${owner}/${input.repoName}`,
    { allowStatuses: [200, 404] },
  );

  if (existing.status === 200) {
    return;
  }

  if (ownerIsOrg) {
    await ensureOrg(baseUrl, owner);
  }

  const createPath = ownerIsOrg
    ? `/api/v1/orgs/${owner}/repos`
    : '/api/v1/user/repos';
  await giteaRequest(baseUrl, createPath, {
    method: 'POST',
    allowStatuses: [201, 409, 422],
    body: {
      name: input.repoName,
      description: input.description ?? '',
      private: input.private ?? true,
      auto_init: true,
      default_branch: input.defaultBranch ?? 'main',
    },
  });
}

async function uploadFile(
  baseUrl: string,
  owner: string,
  repoName: string,
  branch: string,
  sourceRoot: string,
  filePath: string,
): Promise<void> {
  const path = `/api/v1/repos/${owner}/${repoName}/contents/${encodedPath(filePath)}`;
  const current = await giteaRequest<{ sha?: string }>(baseUrl, path, {
    allowStatuses: [200, 404],
  });

  const body: Record<string, unknown> = {
    branch,
    message: `backstage: update ${filePath}`,
    content: (await readFile(resolve(sourceRoot, filePath))).toString('base64'),
  };

  if (current.status === 200 && current.body?.sha) {
    body.sha = current.body.sha;
  }

  await giteaRequest(baseUrl, path, {
    method: 'PUT',
    allowStatuses: [200, 201],
    body,
  });
}

function createGiteaRepoPublishAction() {
  return createTemplateAction({
    id: 'gitea:repo:publish',
    description: 'Create or update a Gitea repository from the scaffolder workspace.',
    supportsDryRun: true,
    schema: {
      input: {
        repoName: z =>
          z
            .string()
            .regex(/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/)
            .describe('Repository name'),
        owner: z => z.string().optional().describe('Gitea owner or organization'),
        description: z => z.string().optional().describe('Repository description'),
        sourcePath: z =>
          z.string().optional().default('.').describe('Workspace-relative source path'),
        defaultBranch: z =>
          z.string().optional().default('main').describe('Default branch'),
        private: z => z.boolean().optional().default(true).describe('Create a private repository'),
      },
      output: {
        repoUrl: z => z.string(),
        remoteUrl: z => z.string(),
        catalogInfoUrl: z => z.string(),
      },
    },
    async handler(ctx) {
      const input = ctx.input as GiteaPublishInput;
      const baseUrl = requiredEnv('GITEA_BASE_URL').replace(/\/+$/, '');
      const publicBaseUrl = (process.env.GITEA_PUBLIC_BASE_URL || baseUrl).replace(/\/+$/, '');
      const owner = input.owner ?? requiredEnv('GITEA_OWNER');
      const ownerIsOrg = boolEnv('GITEA_OWNER_IS_ORG', true);
      const branch = input.defaultBranch ?? 'main';
      const workspaceRoot = resolve(ctx.workspacePath);
      const sourceRoot = resolve(workspaceRoot, input.sourcePath ?? '.');

      if (!isWithin(workspaceRoot, sourceRoot)) {
        throw new Error(`sourcePath must stay inside the workspace: ${input.sourcePath}`);
      }

      const repoUrl = `${publicBaseUrl}/${owner}/${input.repoName}`;
      const remoteUrl = `${baseUrl}/${owner}/${input.repoName}.git`;
      const catalogInfoUrl = `${publicBaseUrl}/${owner}/${input.repoName}/raw/branch/${branch}/catalog-info.yaml`;

      ctx.output('repoUrl', repoUrl);
      ctx.output('remoteUrl', remoteUrl);
      ctx.output('catalogInfoUrl', catalogInfoUrl);

      if (ctx.isDryRun) {
        ctx.logger.info(`Dry-run: would publish ${owner}/${input.repoName} to Gitea`);
        return;
      }

      await ensureRepo(baseUrl, owner, input, ownerIsOrg);

      const files = await listFiles(sourceRoot);
      for (const filePath of files) {
        await uploadFile(baseUrl, owner, input.repoName, branch, sourceRoot, filePath);
      }

      ctx.logger.info(`Published ${files.length} file(s) to ${owner}/${input.repoName}`);
    },
  });
}

export const giteaRepoPublishModule = createBackendModule({
  pluginId: 'scaffolder',
  moduleId: 'gitea-repo-publish',
  register({ registerInit }) {
    registerInit({
      deps: {
        scaffolder: scaffolderActionsExtensionPoint,
      },
      async init({ scaffolder }) {
        scaffolder.addActions(createGiteaRepoPublishAction());
      },
    });
  },
});

export default giteaRepoPublishModule;
