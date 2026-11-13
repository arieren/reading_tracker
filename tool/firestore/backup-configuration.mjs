import { googleRead } from './backup-rest.mjs';

export async function captureConfiguration(
  project,
  databases,
  token,
  read = googleRead,
) {
  async function pages(service, resource, key, parameters = {}) {
    const rows = [];
    let next;
    do {
      const result = await read(service, resource, token, {
        ...parameters,
        pageToken: next,
      });
      rows.push(...(result[key] ?? []));
      next = result.nextPageToken;
    } while (next);
    return rows;
  }
  const configuration = {
    databases,
    indexes: {},
    fields: {},
    releases: [],
    rulesets: [],
  };
  for (const database of databases) {
    const id = database.name.split('/').at(-1),
      parent = `projects/${project}/databases/${id}/collectionGroups/-`;
    configuration.indexes[id] = await pages(
      'firestore.googleapis.com',
      `${parent}/indexes`,
      'indexes',
    );
    configuration.fields[id] = await pages(
      'firestore.googleapis.com',
      `${parent}/fields`,
      'fields',
      {
        filter: 'indexConfig.usesAncestorConfig=false OR ttlConfig:*',
      },
    );
  }
  configuration.releases = (
    await pages(
      'firebaserules.googleapis.com',
      `projects/${project}/releases`,
      'releases',
    )
  ).filter((release) =>
    release.name.split('/releases/')[1]?.startsWith('cloud.firestore'),
  );
  for (const name of new Set(
    configuration.releases.map((release) => release.rulesetName),
  )) {
    const match =
      typeof name === 'string' &&
      name.match(/^projects\/([^/]+)\/rulesets\/([^/]+)$/);
    if (!match || (match[1] !== project && !/^\d+$/.test(match[1])))
      throw new Error('Unexpected deployed ruleset name.');
    configuration.rulesets.push(
      await read('firebaserules.googleapis.com', name, token),
    );
  }
  if (!configuration.rulesets.length)
    throw new Error('No deployed Firestore rules were captured.');
  return configuration;
}
