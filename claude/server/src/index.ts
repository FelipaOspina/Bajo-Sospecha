import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { mathRandom } from './core/Random.js';
import type { EvidenceMapConfig } from './domain/evidence/index.js';
import { createRoleManager, FileRoleConfigSource, InMemoryRoleConfigSource, type RoleSetConfig } from './domain/roles/index.js';
import type { CompiledScenario } from './domain/scenario/ScenarioAdapter.js';
import { FileScenarioSource, loadScenario } from './domain/scenario/ScenarioSource.js';
import { Room } from './net/Room.js';
import { GameGateway } from './net/GameGateway.js';
import { RoomDirectory } from './net/RoomDirectory.js';
import { ProfileService } from './domain/profile/ProfileService.js';
import { JsonFileProfileStore } from './domain/profile/ProfileStore.js';
import type { ProgressionConfig } from './domain/profile/types.js';
import { SkinCatalog, type SkinConfig } from './domain/skins/SkinCatalog.js';
import { WsServer } from './net/WsServer.js';
import { AbilityCatalog, type AbilityConfig } from './domain/abilities/index.js';
import { CosmeticCatalog, type CosmeticConfig } from './domain/cosmetics/CosmeticCatalog.js';

const CONFIG_DIR = fileURLToPath(new URL('../../../../shared/config/', import.meta.url));
const ROLE_SET = process.env.ROLE_SET ?? 'mansion_clasica';
/**
 * SCENARIO=<id> carga shared/config/scenarios/<id>.json.
 * SCENARIO=<ruta.json> carga ese archivo (también casos en formato libre, que se normalizan).
 */
const SCENARIO = process.env.SCENARIO;
const PORT = Number(process.env.PORT ?? 7777);
const TICK_HZ = 20;
/** Perfiles (mock JSON). PROFILES_FILE=<ruta> para guardarlos en otro sitio. */
const PROFILES_FILE = process.env.PROFILES_FILE ?? fileURLToPath(new URL('../../../data/profiles.json', import.meta.url));
/** Jugadores por partida en la cola pública y segundos de cuenta atrás de esas salas. */
const MATCH_SIZE = Number(process.env.MATCH_SIZE ?? 4);
const AUTO_START_MS = Number(process.env.AUTO_START_SECONDS ?? 10) * 1000;

async function loadSetup(): Promise<Pick<CompiledScenario, 'roleSet' | 'map' | 'trial' | 'endings' | 'phaseDurationsMs'>> {
  if (SCENARIO) {
    const compiled = SCENARIO.endsWith('.json')
      ? await loadScenario({ load: async () => JSON.parse(await readFile(SCENARIO, 'utf8')) }, SCENARIO)
      : await loadScenario(new FileScenarioSource(`${CONFIG_DIR}scenarios`), SCENARIO);
    compiled.warnings.forEach((w) => console.warn(`[escenario] ${w}`));
    return compiled;
  }
  const roleSet = (await new FileRoleConfigSource(`${CONFIG_DIR}roles`).load(ROLE_SET)) as RoleSetConfig;
  const map = JSON.parse(await readFile(`${CONFIG_DIR}evidence/${ROLE_SET}.json`, 'utf8')) as EvidenceMapConfig;
  return { roleSet, map, endings: [], phaseDurationsMs: {} };
}

/** Catálogo de skins; si falta el archivo, los jugadores no llevan skin (el cliente elige una). */
async function loadSkins(): Promise<SkinConfig | null> {
  try {
    return JSON.parse(await readFile(`${CONFIG_DIR}skins/skins.json`, 'utf8')) as SkinConfig;
  } catch {
    console.warn('[skins] sin shared/config/skins/skins.json: no se asignan skins');
    return null;
  }
}

/** Habilidades por animal; sin el archivo se juega sin habilidades. */
async function loadAbilities(): Promise<AbilityConfig | null> {
  try {
    return JSON.parse(await readFile(`${CONFIG_DIR}abilities/abilities.json`, 'utf8')) as AbilityConfig;
  } catch {
    console.warn('[habilidades] sin shared/config/abilities/abilities.json: partidas sin habilidades');
    return null;
  }
}

/** Cosméticos de la tienda y del pase; sin el archivo no hay cosméticos. */
async function loadCosmetics(): Promise<CosmeticConfig | null> {
  try {
    return JSON.parse(await readFile(`${CONFIG_DIR}cosmetics/cosmetics.json`, 'utf8')) as CosmeticConfig;
  } catch {
    console.warn('[cosméticos] sin shared/config/cosmetics/cosmetics.json: tienda vacía');
    return null;
  }
}

/** Progresión (perfil, Executive Pass, tienda); sin el archivo no hay perfiles. */
async function loadProgression(): Promise<ProgressionConfig | null> {
  try {
    return JSON.parse(await readFile(`${CONFIG_DIR}progression/progression.json`, 'utf8')) as ProgressionConfig;
  } catch {
    console.warn('[perfil] sin shared/config/progression/progression.json: sin perfiles ni pase');
    return null;
  }
}

async function main() {
  const setup = await loadSetup();
  const skins = await loadSkins();
  const progression = await loadProgression();
  const abilityConfig = await loadAbilities();
  const abilities = abilityConfig ? new AbilityCatalog(abilityConfig) : undefined;   // valida al arrancar
  const cosmeticConfig = await loadCosmetics();
  const cosmetics = cosmeticConfig ? new CosmeticCatalog(cosmeticConfig) : undefined;
  // Validar una vez al arrancar (falla rápido si el escenario está mal).
  await createRoleManager(new InMemoryRoleConfigSource({ [setup.roleSet.id]: setup.roleSet }), mathRandom).roleManager.loadRoleSet(setup.roleSet.id);

  const catalog = skins ? new SkinCatalog(skins, mathRandom) : undefined;
  const store = new JsonFileProfileStore(PROFILES_FILE);
  const profiles = progression
    ? new ProfileService(progression, store, catalog ?? { has: () => false }, undefined, undefined, cosmetics)
    : undefined;
  const gateway = new GameGateway(profiles, MATCH_SIZE);
  const directory = new RoomDirectory((code, visibility) => {
    // Cada sala: su propio RoleManager (reparto secreto independiente).
    const { roleManager, objectives } = createRoleManager(new InMemoryRoleConfigSource({ [setup.roleSet.id]: setup.roleSet }), mathRandom);
    roleManager.useRoleSet(structuredClone(setup.roleSet));
    return new Room(code, {
      roles: roleManager, objectives, map: structuredClone(setup.map), trial: setup.trial, endings: setup.endings,
      skins: catalog, abilities,
    }, gateway, {
      phaseDurationsMs: setup.phaseDurationsMs,
      visibility,
      autoStartDelayMs: AUTO_START_MS,
      onResolved: (resolution) => gateway.rewardMatch(resolution),
    });
  });
  gateway.attach(directory);
  new WsServer(PORT, gateway).listen();
  console.log(`Escenario: ${setup.roleSet.name} · perfiles en ${PROFILES_FILE}`);

  setInterval(() => directory.tick(), 1000 / TICK_HZ);
  // Guardar perfiles pendientes al cerrar.
  for (const sig of ['SIGINT', 'SIGTERM'] as const) process.on(sig, () => { store.flush(); process.exit(0); });
}

main().catch((e) => { console.error(e); process.exit(1); });
