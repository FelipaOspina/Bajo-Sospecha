import { strict as assert } from 'node:assert';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { SeededRandom } from '../src/core/Random.js';
import { createRoleManager, InMemoryRoleConfigSource } from '../src/domain/roles/index.js';
import { FileScenarioSource, loadScenario } from '../src/domain/scenario/ScenarioSource.js';
import { DEV, LEGACY_PATH, loadLegacy, loadNative } from './helpers.js';

const EXPECTED: Record<number, string[]> = {
  4: ['ROLE_CEO', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER'],
  5: ['ROLE_CEO', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_SECURITY'],
  6: ['ROLE_ACCOMPLICE', 'ROLE_CEO', 'ROLE_CTO', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_SECURITY'],
  7: ['ROLE_ACCOMPLICE', 'ROLE_CEO', 'ROLE_CTO', 'ROLE_EMPLOYEE', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_SECURITY'],
  8: ['ROLE_ACCOMPLICE', 'ROLE_CEO', 'ROLE_CTO', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_INVESTOR', 'ROLE_LEAKER', 'ROLE_SECURITY'],
  9: ['ROLE_ACCOMPLICE', 'ROLE_CEO', 'ROLE_CTO', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_INVESTOR', 'ROLE_JOURNALIST', 'ROLE_LEAKER', 'ROLE_SECURITY'],
  10: ['ROLE_ACCOMPLICE', 'ROLE_CEO', 'ROLE_CFO', 'ROLE_CTO', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_INVESTOR', 'ROLE_JOURNALIST', 'ROLE_LEAKER', 'ROLE_SECURITY'],
  11: ['ROLE_ACCOMPLICE', 'ROLE_CEO', 'ROLE_CFO', 'ROLE_CTO', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_INVESTOR', 'ROLE_JOURNALIST', 'ROLE_LEAKER', 'ROLE_SECURITY'],
  12: ['ROLE_ACCOMPLICE', 'ROLE_CEO', 'ROLE_CFO', 'ROLE_CTO', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_EMPLOYEE', 'ROLE_INVESTOR', 'ROLE_JOURNALIST', 'ROLE_LEAKER', 'ROLE_SECURITY'],
};

test('ambos casos cargan con loadScenario (legacy por ruta y nativo por id)', async () => {
  const legacy = await loadScenario({ load: async () => JSON.parse(await readFile(LEGACY_PATH, 'utf8')) }, LEGACY_PATH);
  const native = await loadScenario(new FileScenarioSource(`${DEV}shared/config/scenarios`), 'nexuscore_fraude');
  for (const c of [legacy, native]) {
    assert.equal(c.roleSet.minPlayers, 4);
    assert.equal(c.roleSet.maxPlayers, 12);
    assert.equal(c.map.evidence.length, 16);
    assert.equal(c.phaseDurationsMs.investigation, 300_000);
    assert.equal(c.phaseDurationsMs.emergency, 75_000);
    assert.ok(c.endings.some((e) => e.id === 'silencio_total'));
    assert.equal(c.emergency.maxPerMatch, 3);
    assert.ok(c.emergency.expelEndsGame.ROLE_CEO);
    const acc = c.roleSet.roles.find((r) => r.id === 'ROLE_ACCOMPLICE')!;
    assert.deepEqual([acc.team, acc.minPlayers, acc.powers, acc.knowsTeammates], ['culpables', 6, ['silence'], true]);
    assert.deepEqual(c.roleSet.roles.find((r) => r.id === 'ROLE_SECURITY')!.powers, ['escort']);
    assert.deepEqual(c.roleSet.roles.find((r) => r.id === 'ROLE_CEO')!.motiveTargets, ['ROLE_LEAKER']);
    const nda = c.map.evidence.find((e) => e.id === 'CLUE_LAWYER_NDA')!;
    assert.deepEqual(nda.incriminates, ['ROLE_ACCOMPLICE', 'ROLE_CEO']);
    assert.deepEqual(c.map.interactables.find((i) => i.id === 'spawn_CLUE_BURNER_PHONE')!.position, { x: 3700, y: 1080 });
  }
  assert.ok(native.trial!.options!.some((o) => o.id === 'despedir_abogado' && o.accuses_role === 'ROLE_ACCOMPLICE'));
  assert.ok(native.trial!.options!.some((o) => o.id === 'despedir_cfo'));
  assert.deepEqual(native.endings.find((e) => e.id === 'ceo_gana')!.winners.roles, ['ROLE_CEO', 'ROLE_ACCOMPLICE', 'ROLE_CFO']);
  assert.deepEqual(native.endings.find((e) => e.id === 'empleados')!.winners.roles, ['ROLE_EMPLOYEE', 'ROLE_SECURITY']);
});

for (const [name, load] of [['nativo', loadNative], ['legacy', loadLegacy]] as const) {
  test(`reparto n=4..12 (${name})`, () => {
    const c = load();
    for (let seed = 1; seed <= 5; seed++) {
      const { roleManager } = createRoleManager(new InMemoryRoleConfigSource({ [c.roleSet.id]: c.roleSet }), new SeededRandom(seed));
      roleManager.useRoleSet(structuredClone(c.roleSet));
      for (let n = 4; n <= 12; n++) {
        const roles = [...roleManager.assignRoles(Array.from({ length: n }, (_, i) => `p${i}`)).values()].sort();
        assert.deepEqual(roles, EXPECTED[n], `n=${n} seed=${seed}`);
      }
    }
  });
}

test('el CEO y sus cómplices se conocen', () => {
  const c = loadNative();
  const { roleManager } = createRoleManager(new InMemoryRoleConfigSource({ [c.roleSet.id]: c.roleSet }), new SeededRandom(1));
  roleManager.useRoleSet(structuredClone(c.roleSet));
  roleManager.assignRoles(['a', 'b', 'c', 'd', 'e', 'f']);
  const ceo = ['a', 'b', 'c', 'd', 'e', 'f'].find((p) => roleManager.getRoleOf(p)!.id === 'ROLE_CEO')!;
  const acc = ['a', 'b', 'c', 'd', 'e', 'f'].find((p) => roleManager.getRoleOf(p)!.id === 'ROLE_ACCOMPLICE')!;
  assert.deepEqual(roleManager.knownTeammates(ceo), [acc]);
  assert.deepEqual(roleManager.knownTeammates(acc), [ceo]);
});
