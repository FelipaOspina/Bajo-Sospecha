import type { Condition, ResolutionContext } from './types.js';

type Eval = (c: Condition) => boolean;

/** Una clave de condición = un handler. Añadir condiciones no toca GameResolution. */
export interface IConditionHandler {
  readonly key: string;
  validate(value: unknown, validateNested: (c: unknown) => string[]): string[];
  evaluate(value: unknown, ctx: ResolutionContext, evalNested: Eval): boolean;
}

const strList = (v: unknown): string[] => (typeof v === 'string' ? [v] : Array.isArray(v) ? v.map(String) : []);
const needList = (key: string) => (v: unknown) =>
  (Array.isArray(v) && v.length) || typeof v === 'string' ? [] : [`${key} necesita un id o una lista`];

export class ConditionRegistry {
  private readonly handlers = new Map<string, IConditionHandler>();

  register(h: IConditionHandler): this { this.handlers.set(h.key, h); return this; }

  validate(c: unknown): string[] {
    if (!c || typeof c !== 'object' || Array.isArray(c)) return ['la condición debe ser un objeto'];
    const keys = Object.keys(c);
    if (keys.length !== 1) return [`la condición debe tener exactamente una clave (tiene: ${keys.join(', ') || 'ninguna'})`];
    const h = this.handlers.get(keys[0]!);
    if (!h) return [`condición desconocida "${keys[0]}"`];
    return h.validate((c as Condition)[keys[0]!], (n) => this.validate(n));
  }

  evaluate(c: Condition, ctx: ResolutionContext): boolean {
    const [key] = Object.keys(c);
    const h = key ? this.handlers.get(key) : undefined;
    if (!h) throw new Error(`Condición desconocida: ${key}`);
    return h.evaluate(c[key!], ctx, (n) => this.evaluate(n, ctx));
  }
}

const nestedList = (key: string): IConditionHandler['validate'] => (v, nested) =>
  Array.isArray(v) && v.length ? v.flatMap(nested) : [`${key} necesita una lista de condiciones`];

export const createDefaultConditionRegistry = () =>
  new ConditionRegistry()
    .register({
      key: 'verdict',
      validate: needList('verdict'),
      evaluate: (v, ctx) => ctx.verdictOptionId !== null && strList(v).includes(ctx.verdictOptionId),
    })
    .register({
      key: 'accused_role',
      validate: needList('accused_role'),
      evaluate: (v, ctx) => ctx.accused.some((p) => strList(v).includes(ctx.roleOf(p) ?? '')),
    })
    .register({
      key: 'revealed_all',
      validate: needList('revealed_all'),
      evaluate: (v, ctx) => strList(v).every((id) => ctx.revealed.has(id)),
    })
    .register({
      key: 'revealed_any',
      validate: needList('revealed_any'),
      evaluate: (v, ctx) => strList(v).some((id) => ctx.revealed.has(id)),
    })
    .register({
      key: 'revealed_count',
      validate: (v) => {
        const o = v as { tags?: unknown; min?: unknown };
        return Array.isArray(o?.tags) && Number.isInteger(o?.min) ? [] : ['revealed_count necesita { tags: [...], min: n }'];
      },
      evaluate: (v, ctx) => {
        const o = v as { tags: string[]; min: number };
        return ctx.revealedTags.filter((tags) => tags.some((t) => o.tags.includes(t))).length >= o.min;
      },
    })
    .register({
      key: 'destroyed_all',
      validate: needList('destroyed_all'),
      evaluate: (v, ctx) => strList(v).every((id) => ctx.destroyed.has(id)),
    })
    .register({
      key: 'destroyed_any',
      validate: needList('destroyed_any'),
      evaluate: (v, ctx) => strList(v).some((id) => ctx.destroyed.has(id)),
    })
    .register({
      key: 'held_by_role',
      validate: (v) => {
        const o = v as { role?: unknown; evidence?: unknown };
        return typeof o?.role === 'string' && typeof o?.evidence === 'string' ? [] : ['held_by_role necesita { role, evidence }'];
      },
      evaluate: (v, ctx) => {
        const o = v as { role: string; evidence: string };
        return ctx.holdersOf(o.evidence).some((p) => ctx.roleOf(p) === o.role);
      },
    })
    .register({ key: 'all', validate: nestedList('all'), evaluate: (v, _c, ev) => (v as Condition[]).every(ev) })
    .register({ key: 'any', validate: nestedList('any'), evaluate: (v, _c, ev) => (v as Condition[]).some(ev) })
    .register({ key: 'not', validate: (v, nested) => nested(v), evaluate: (v, _c, ev) => !ev(v as Condition) });
