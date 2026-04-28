import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { uploadFile } from './giteaRepoPublish';

const originalFetch = global.fetch;
const originalEnv = process.env;

describe('gitea repo publish action', () => {
  let sourceRoot: string;
  let requests: Array<{ url: string; method: string; body?: any }>;

  beforeEach(async () => {
    sourceRoot = await mkdtemp(join(tmpdir(), 'gitea-publish-'));
    requests = [];
    process.env = {
      ...originalEnv,
      GITEA_USERNAME: 'gitea-admin',
      GITEA_PASSWORD: 'platform-password',
    };
  });

  afterEach(async () => {
    global.fetch = originalFetch;
    process.env = originalEnv;
    await rm(sourceRoot, { recursive: true, force: true });
  });

  function mockFetch(getStatus: number, getBody: object) {
    global.fetch = jest.fn(async (url, init) => {
      const method = init?.method ?? 'GET';
      requests.push({
        url: String(url),
        method,
        body: init?.body ? JSON.parse(String(init.body)) : undefined,
      });

      if (method === 'GET') {
        return new Response(JSON.stringify(getBody), { status: getStatus });
      }

      return new Response(JSON.stringify({ ok: true }), { status: 201 });
    }) as typeof fetch;
  }

  it('creates new nested files with POST', async () => {
    await mkdir(join(sourceRoot, '.gitea', 'workflows'), { recursive: true });
    await writeFile(join(sourceRoot, '.gitea', 'workflows', 'build.yaml'), 'name: build\n');
    mockFetch(404, { message: 'not found' });

    await uploadFile(
      'http://gitea-http.gitea.svc.cluster.local:3000',
      'platform',
      'bob',
      'main',
      sourceRoot,
      '.gitea/workflows/build.yaml',
    );

    expect(requests).toHaveLength(2);
    expect(requests[1]).toMatchObject({
      method: 'POST',
      url: 'http://gitea-http.gitea.svc.cluster.local:3000/api/v1/repos/platform/bob/contents/.gitea/workflows/build.yaml',
    });
    expect(requests[1].body).toMatchObject({
      branch: 'main',
      message: 'backstage: update .gitea/workflows/build.yaml',
    });
    expect(requests[1].body.sha).toBeUndefined();
  });

  it('updates existing files with PUT and the current SHA', async () => {
    await writeFile(join(sourceRoot, 'README.md'), '# bob\n');
    mockFetch(200, { sha: 'existing-file-sha' });

    await uploadFile(
      'http://gitea-http.gitea.svc.cluster.local:3000',
      'platform',
      'bob',
      'main',
      sourceRoot,
      'README.md',
    );

    expect(requests).toHaveLength(2);
    expect(requests[1]).toMatchObject({
      method: 'PUT',
      url: 'http://gitea-http.gitea.svc.cluster.local:3000/api/v1/repos/platform/bob/contents/README.md',
    });
    expect(requests[1].body).toMatchObject({
      branch: 'main',
      sha: 'existing-file-sha',
    });
  });
});
