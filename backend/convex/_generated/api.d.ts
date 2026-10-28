/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as ai from "../ai.js";
import type * as aiPrompts from "../aiPrompts.js";
import type * as billing from "../billing.js";
import type * as folders from "../folders.js";
import type * as grading from "../grading.js";
import type * as http from "../http.js";
import type * as library from "../library.js";
import type * as notes from "../notes.js";
import type * as plans from "../plans.js";
import type * as problems from "../problems.js";
import type * as questions from "../questions.js";
import type * as rows from "../rows.js";
import type * as scheduling from "../scheduling.js";
import type * as stripeActions from "../stripeActions.js";
import type * as stripeSync from "../stripeSync.js";
import type * as sync from "../sync.js";
import type * as today from "../today.js";
import type * as users from "../users.js";
import type * as validators from "../validators.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  ai: typeof ai;
  aiPrompts: typeof aiPrompts;
  billing: typeof billing;
  folders: typeof folders;
  grading: typeof grading;
  http: typeof http;
  library: typeof library;
  notes: typeof notes;
  plans: typeof plans;
  problems: typeof problems;
  questions: typeof questions;
  rows: typeof rows;
  scheduling: typeof scheduling;
  stripeActions: typeof stripeActions;
  stripeSync: typeof stripeSync;
  sync: typeof sync;
  today: typeof today;
  users: typeof users;
  validators: typeof validators;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
