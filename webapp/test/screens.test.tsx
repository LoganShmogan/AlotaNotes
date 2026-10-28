import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ConvexError } from "convex/values";
import { beforeEach, describe, expect, test, vi } from "vitest";
import { answer, at, backend, calls, handle, nav } from "./mocks";
import { AppShell } from "@/components/AppShell";
import { AuthFrame } from "@/components/AuthFrame";
import { NotesWorkspace } from "@/components/NotesWorkspace";
import { PlanPanel } from "@/components/PlanPanel";
import { SettingsView } from "@/components/SettingsView";
import { TodayDashboard } from "@/components/TodayDashboard";
import { matches, sortProblems, Tracker } from "@/components/Tracker";
import { Dialog } from "@/components/ui";
import { newCard, reviewCard } from "@/lib/api";

beforeEach(() => {
  backend.reset();
  at("/");
  vi.spyOn(window, "confirm").mockReturnValue(true);
});

describe("AppShell", () => {
  test("marks the current section, and Ctrl/⌘+1-5 switch sections", () => {
    at("/notes");
    render(<AppShell>content</AppShell>);
    const current = screen.getAllByRole("link", { current: "page" });
    expect(current.map((l) => l.textContent)).toEqual(["Notes", "Notes"]); // rail and bottom bar
    fireEvent.keyDown(window, { key: "3", ctrlKey: true });
    expect(nav.push).toHaveBeenCalledWith("/tracker");
    fireEvent.keyDown(window, { key: "1", metaKey: true });
    expect(nav.push).toHaveBeenLastCalledWith("/today");
    fireEvent.keyDown(window, { key: "2" });
    fireEvent.keyDown(window, { key: "9", ctrlKey: true });
    fireEvent.keyDown(window, { key: "2", ctrlKey: true, shiftKey: true });
    expect(nav.push).toHaveBeenCalledTimes(2);
  });

  test("the sign-in frame shows the brand", () => {
    render(<AuthFrame>form</AuthFrame>);
    expect(screen.getByText(/right before you would forget it/)).toBeInTheDocument();
  });
});

describe("Today", () => {
  const summary = (over = {}) => ({ dueQuestions: 0, reviewsToday: 3, attemptsToday: 1, problemsDue: [], forecast: [], ...over });

  test("all caught up", () => {
    answer("today:summary", undefined);
    const { rerender } = render(<TodayDashboard />);
    expect(screen.getByRole("status")).toBeInTheDocument();
    answer("today:summary", summary());
    rerender(<TodayDashboard />);
    expect(screen.getByText("All caught up")).toBeInTheDocument();
    expect(screen.getByText("No problems are due.")).toBeInTheDocument();
  });

  test("due questions start a quiz and due problems link to the tracker", () => {
    answer("today:summary", (args: { now: string; dayStart: string }) => {
      expect(Date.parse(args.dayStart)).toBeLessThanOrEqual(Date.parse(args.now));
      return summary({
        dueQuestions: 4,
        problemsDue: [{ uid: "p1", title: "Two Sum", difficulty: "easy", nextDueAt: "" }],
        forecast: [new Date(Date.now() + 86_400_000).toISOString()],
      });
    });
    render(<TodayDashboard />);
    expect(screen.getByRole("link", { name: "Start quiz (4)" })).toHaveAttribute("href", "/quiz");
    expect(screen.getByRole("link", { name: /Two Sum/ })).toHaveAttribute("href", "/tracker?p=p1");
    expect(within(screen.getByRole("region", { name: "Next 7 days" })).getByTitle("Today: 5")).toBeInTheDocument();
  });
});

describe("Notes", () => {
  const folders = [
    { uid: "f1", name: "Biology", parentFolderUid: null },
    { uid: "f2", name: "Cells", parentFolderUid: "f1" },
  ];

  test("lists top-level folders and creates one", async () => {
    answer("folders:list", folders);
    handle("folders:create", () => "f9");
    render(<NotesWorkspace />);
    expect(screen.getByRole("button", { name: /Biology/ })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Cells" })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: /Biology/ }));
    expect(nav.push).toHaveBeenCalledWith("/?folder=f1");

    await userEvent.click(screen.getByRole("button", { name: "New folder" }));
    const dialog = screen.getByRole("dialog", { name: "New subject folder" });
    await userEvent.click(within(dialog).getByRole("button", { name: "Create" }));
    expect(within(dialog).getByRole("alert")).toHaveTextContent("Folder name can't be empty.");
    await userEvent.type(within(dialog).getByLabelText("Folder name"), "Chemistry");
    await userEvent.click(within(dialog).getByRole("button", { name: "Create" }));
    await waitFor(() => expect(calls("folders:create")).toEqual([{ name: "Chemistry", parentFolderUid: null }]));
    expect(nav.push).toHaveBeenLastCalledWith("/?folder=f9");
  });

  test("inside a folder: subfolders, notes, new note, rename and delete", async () => {
    at("/notes", "folder=f1");
    answer("folders:list", folders);
    answer("notes:listByFolder", [{ uid: "n1", title: "Mitosis", preview: "Cells divide", updatedAt: "", sourceFilename: null }]);
    handle("notes:create", () => "n2");
    render(<NotesWorkspace />);
    expect(screen.getByRole("heading", { name: "Biology" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Cells" })).toBeInTheDocument();
    expect(screen.getByText("Cells divide")).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: /Mitosis/ }));
    expect(nav.push).toHaveBeenLastCalledWith("/notes?folder=f1&note=n1");

    await userEvent.click(screen.getByRole("button", { name: "New note" }));
    const dialog = screen.getByRole("dialog", { name: "New note" });
    await userEvent.type(within(dialog).getByLabelText("Title"), "Meiosis");
    await userEvent.click(within(dialog).getByRole("button", { name: "Create" }));
    await waitFor(() => expect(calls("notes:create")).toEqual([{ folderUid: "f1", title: "Meiosis", body: "" }]));

    await userEvent.click(screen.getByRole("button", { name: "Rename" }));
    const rename = screen.getByRole("dialog", { name: "Rename folder" });
    expect(within(rename).getByLabelText("Folder name")).toHaveValue("Biology");

    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    await waitFor(() => expect(calls("folders:remove")).toEqual([{ uid: "f1" }]));
    expect(nav.push).toHaveBeenLastCalledWith("/notes");

    await userEvent.click(screen.getByRole("button", { name: "← All folders" }));
  });

  test("a note opens in the editor: save, generate, edit and pause questions", async () => {
    at("/notes", "folder=f1&note=n1");
    answer("folders:list", folders);
    answer("notes:listByFolder", []);
    answer("notes:get", { uid: "n1", title: "Cells", body: "Mitochondria make ATP.", folderUid: "f1", sortOrder: 0, createdAt: "", updatedAt: "", sourceFilename: null });
    answer("questions:listByNote", [
      { uid: "q1", prompt: "What makes ATP?", expectedAnswer: "Mitochondria", questionType: "short_answer", active: true, isManuallyEdited: false, choices: [] },
      {
        uid: "q2",
        prompt: "Pick",
        expectedAnswer: "B",
        questionType: "multiple_choice",
        active: false,
        isManuallyEdited: true,
        choices: [
          { uid: "c1", text: "A", isCorrect: false },
          { uid: "c2", text: "B", isCorrect: true },
        ],
      },
    ]);
    handle("ai:generateQuestions", () => ({ questions: [{ prompt: "p" }], usage: { used: 3, limit: 20 } }));
    render(<NotesWorkspace />);

    expect(screen.getByRole("button", { name: "Saved" })).toBeDisabled();
    await userEvent.type(screen.getByLabelText("Body"), " Ribosomes make proteins.");
    fireEvent.keyDown(window, { key: "s", ctrlKey: true });
    await waitFor(() => expect(calls("notes:update")).toHaveLength(1));
    expect(calls("notes:update")[0]).toEqual({ uid: "n1", title: "Cells", body: "Mitochondria make ATP. Ribosomes make proteins." });
    expect(await screen.findByText("Saved.")).toBeInTheDocument();

    await userEvent.selectOptions(screen.getByLabelText("Question format"), "multiple_choice");
    await userEvent.click(screen.getByRole("button", { name: "Generate" }));
    expect(await screen.findByText("Generated 1 question(s). 3 of 20 this month.")).toBeInTheDocument();
    expect(calls("ai:generateQuestions")[0]).toMatchObject({ numQuestions: 5, questionFormat: "multiple_choice" });
    expect(calls("questions:saveGenerated")[0]).toEqual({ noteUid: "n1", questions: [{ prompt: "p" }] });

    await userEvent.click(screen.getAllByRole("button", { name: "Pause" })[0]);
    expect(calls("questions:setActive")).toEqual([{ uid: "q1", active: false }]);
    await userEvent.click(screen.getByRole("button", { name: "Resume" }));
    await userEvent.click(screen.getAllByRole("button", { name: "Delete" })[2]);
    expect(calls("questions:remove")).toEqual([{ uid: "q1" }]);

    await userEvent.click(screen.getAllByRole("button", { name: "Edit" })[1]);
    const editor = screen.getByRole("dialog", { name: "Edit question" });
    await userEvent.click(within(editor).getByLabelText("Choice 1 is correct"));
    await userEvent.clear(within(editor).getByLabelText("Choice 1"));
    await userEvent.type(within(editor).getByLabelText("Choice 1"), "Z");
    await userEvent.click(within(editor).getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(calls("questions:update")).toEqual([
        { uid: "q2", prompt: "Pick", expectedAnswer: "Z", choices: [{ text: "Z", isCorrect: true }, { text: "B", isCorrect: false }] },
      ]),
    );
  });

  test("generation errors are explained, and huge notes can't be saved", async () => {
    at("/notes", "folder=f1&note=n1");
    answer("folders:list", folders);
    answer("notes:listByFolder", []);
    answer("notes:get", { uid: "n1", title: "Cells", body: "x", folderUid: "f1", sortOrder: 0, createdAt: "", updatedAt: "", sourceFilename: null });
    answer("questions:listByNote", []);
    handle("ai:generateQuestions", () => {
      throw new ConvexError({ code: "AI_LIMIT_REACHED", message: "You've used all 20 AI generations this month." });
    });
    render(<NotesWorkspace />);
    expect(screen.getByText(/No questions yet/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Generate" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("used all 20");

    fireEvent.change(screen.getByLabelText("Body"), { target: { value: "x".repeat(205 * 1024) } });
    expect(screen.getByText(/over 200 KB/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
  });

  test("a deleted note says so", async () => {
    at("/notes", "note=gone");
    answer("folders:list", []);
    answer("notes:get", null);
    render(<NotesWorkspace />);
    expect(screen.getByText("This note no longer exists.")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Back" }));
    expect(nav.push).toHaveBeenCalledWith("/notes");
  });
});

describe("Tracker", () => {
  const card = reviewCard(newCard(0), 3, 0);
  const problems = [
    { uid: "p1", title: "Two Sum", difficulty: "easy" as const, tags: ["array"], card, attempts: 1, lastSolved: true, url: null, platform: "", createdAt: "", updatedAt: "" },
    { uid: "p2", title: "LRU Cache", difficulty: "hard" as const, tags: ["design"], card: null, attempts: 0, lastSolved: null, url: null, platform: "", createdAt: "", updatedAt: "" },
  ];

  test("filters and sorts", () => {
    const now = Date.now();
    expect(problems.filter((p) => matches(p, "due", "", now)).map((p) => p.uid)).toEqual(["p1"]);
    expect(problems.filter((p) => matches(p, "new", "", now)).map((p) => p.uid)).toEqual(["p2"]);
    expect(problems.filter((p) => matches(p, "hard", "", now)).map((p) => p.uid)).toEqual(["p2"]);
    expect(problems.filter((p) => matches(p, "all", "ARR", now)).map((p) => p.uid)).toEqual(["p1"]);
    expect(sortProblems(problems, "title", now).map((p) => p.uid)).toEqual(["p2", "p1"]);
    expect(sortProblems(problems, "difficulty", now).map((p) => p.uid)).toEqual(["p1", "p2"]);
    expect(sortProblems(problems, "due", now).map((p) => p.uid)).toEqual(["p1", "p2"]);
    expect(sortProblems(problems, "recall", now).map((p) => p.uid)).toEqual(["p2", "p1"]);
    expect(sortProblems(problems, "attempts", now).map((p) => p.uid)).toEqual(["p2", "p1"]);
  });

  test("lists, filters, switches to a table, and opens one", async () => {
    at("/tracker");
    answer("problems:list", problems);
    render(<Tracker />);
    expect(screen.getByText("Not tried yet")).toBeInTheDocument();
    expect(screen.getByText(/Due now · 1 attempt/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Not tried" }));
    expect(screen.queryByText("Two Sum")).not.toBeInTheDocument();
    await userEvent.type(screen.getByLabelText("Search problems"), "zzz");
    expect(screen.getByText("Nothing matches.")).toBeInTheDocument();
    await userEvent.clear(screen.getByLabelText("Search problems"));
    await userEvent.click(screen.getByRole("button", { name: "All" }));

    await userEvent.click(screen.getByRole("button", { name: "Table" }));
    const table = screen.getByRole("table");
    await userEvent.click(within(table).getByRole("button", { name: "Name" }));
    expect(within(table).getAllByRole("row")[1]).toHaveTextContent("LRU Cache");
    await userEvent.click(within(table).getAllByRole("row")[2]);
    expect(nav.push).toHaveBeenCalledWith("/tracker?p=p1");
  });

  test("an empty tracker, and adding a problem", async () => {
    at("/tracker");
    answer("problems:list", []);
    handle("problems:create", () => "p9");
    render(<Tracker />);
    expect(screen.getByText("No problems yet")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Add problem" }));
    const dialog = screen.getByRole("dialog", { name: "Add a problem" });
    await userEvent.type(within(dialog).getByLabelText("Title"), "Two Sum");
    await userEvent.selectOptions(within(dialog).getByLabelText("Difficulty"), "easy");
    await userEvent.type(within(dialog).getByLabelText("Tags"), "array, hash");
    await userEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    await waitFor(() => expect(calls("problems:create")[0]).toMatchObject({ title: "Two Sum", difficulty: "easy", url: null, tags: ["array", " hash"] }));
    expect(nav.push).toHaveBeenCalledWith("/tracker?p=p9");
  });

  test("the detail shows the problem; logging an attempt reschedules it", async () => {
    at("/tracker", "p=p1");
    answer("problems:list", problems);
    answer("problems:get", {
      ...problems[0],
      url: "https://leetcode.com/problems/two-sum",
      platform: "LeetCode",
      solution: "hash map",
      notes: "watch duplicates",
      attempts: [{ uid: "a1", attemptedAt: "2026-10-01T00:00:00.000Z", solved: true, durationMinutes: 12, rating: 3, notes: "fine" }],
    });
    render(<Tracker />);
    expect(screen.getByRole("heading", { name: "Two Sum" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Open problem" })).toHaveAttribute("rel", "noopener noreferrer");
    expect(screen.getByText("hash map")).toBeInTheDocument();
    expect(screen.getByText(/12 min/)).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Log attempt" }));
    const dialog = screen.getByRole("dialog", { name: "Log an attempt: Two Sum" });
    await userEvent.click(within(dialog).getByRole("button", { name: "Not solved" }));
    await userEvent.type(within(dialog).getByLabelText("Minutes taken (optional)"), "2.5");
    await userEvent.click(within(dialog).getByRole("button", { name: /Hard/ }));
    expect(within(dialog).getByRole("alert")).toHaveTextContent("whole number");
    await userEvent.clear(within(dialog).getByLabelText("Minutes taken (optional)"));
    await userEvent.type(within(dialog).getByLabelText("Minutes taken (optional)"), "25");
    await userEvent.click(within(dialog).getByRole("button", { name: /Hard/ }));
    await waitFor(() =>
      expect(calls("problems:logAttempt")).toEqual([{ uid: "p1", solved: false, rating: 2, durationMinutes: 25, notes: "", retention: 0.9 }]),
    );

    await userEvent.click(screen.getByRole("button", { name: "Edit" }));
    const form = screen.getByRole("dialog", { name: "Edit problem" });
    expect(within(form).getByLabelText("Tags")).toHaveValue("array");
    await userEvent.click(within(form).getByRole("button", { name: "Save" }));
    await waitFor(() => expect(calls("problems:update")[0]).toMatchObject({ uid: "p1", title: "Two Sum", platform: "LeetCode" }));

    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    await waitFor(() => expect(calls("problems:remove")).toEqual([{ uid: "p1" }]));
  });

  test("a save that fails shows why", async () => {
    at("/tracker");
    answer("problems:list", []);
    handle("problems:create", () => {
      throw new ConvexError({ code: "INVALID_REQUEST", message: "Links must start with http:// or https://." });
    });
    render(<Tracker />);
    await userEvent.click(screen.getByRole("button", { name: "Add problem" }));
    const dialog = screen.getByRole("dialog");
    await userEvent.type(within(dialog).getByLabelText("Title"), "X");
    await userEvent.click(within(dialog).getByRole("button", { name: "Save" }));
    expect(await within(dialog).findByRole("alert")).toHaveTextContent("Links must start");
    await userEvent.click(within(dialog).getByRole("button", { name: "Cancel" }));
  });
});

describe("Plan and Settings", () => {
  const free = { plan: "free", planName: "Free", aiNotes: { period: "2026-10", used: 20, limit: 20 }, subscription: null, upgradeAvailable: true };
  const pro = {
    ...free,
    plan: "pro",
    planName: "Pro",
    aiNotes: { period: "2026-10", used: 3, limit: 500 },
    subscription: { status: "active", interval: "year", currentPeriodEnd: Date.UTC(2027, 9, 28), cancelAtPeriodEnd: false },
  };

  test("Free: upgrade goes to Stripe Checkout", async () => {
    const assign = vi.fn();
    vi.stubGlobal("location", { ...window.location, assign });
    answer("billing:me", free);
    handle("stripeActions:createCheckoutSession", (args) => ({ url: `https://checkout.stripe.test/${args.interval}` }));
    render(<PlanPanel />);
    expect(screen.getByText("QuillFin's AI this month: 20 of 20 notes")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Upgrade yearly" }));
    await waitFor(() => expect(assign).toHaveBeenCalledWith("https://checkout.stripe.test/year"));
    vi.unstubAllGlobals();
  });

  test("Pro: renewal and the Billing Portal; a failure shows why", async () => {
    answer("billing:me", pro);
    handle("stripeActions:createPortalSession", () => {
      throw new ConvexError({ code: "NO_BILLING_ACCOUNT", message: "You don't have a subscription to manage yet." });
    });
    render(<PlanPanel checkout="success" />);
    expect(screen.getByText("You're on Pro. Thank you!")).toBeInTheDocument();
    expect(screen.getByText(/Renews on .*2027 \(yearly\)/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Manage plan" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("subscription to manage");
  });

  test("a cancelled plan, a pending checkout, and upgrades not open yet", () => {
    answer("billing:me", { ...pro, subscription: { ...pro.subscription, cancelAtPeriodEnd: true } });
    const { rerender } = render(<PlanPanel />);
    expect(screen.getByText(/Ends on/)).toBeInTheDocument();
    answer("billing:me", { ...free, upgradeAvailable: false });
    rerender(<PlanPanel checkout="success" />);
    expect(screen.getByText(/being confirmed/)).toBeInTheDocument();
    expect(screen.getByText("Upgrades aren't open yet.")).toBeInTheDocument();
    answer("billing:me", undefined);
    rerender(<PlanPanel />);
    expect(screen.getByRole("status")).toBeInTheDocument();
  });

  test("Settings: sections, theme and target recall", async () => {
    at("/settings", "section=appearance");
    answer("billing:me", free);
    render(<SettingsView />);
    const wide = screen.getByRole("navigation", { name: "Settings sections" });
    expect(within(wide).getByRole("button", { name: "Appearance" })).toHaveAttribute("aria-current", "true");

    await userEvent.click(screen.getAllByRole("radio", { name: "Dark" })[0]);
    expect(document.documentElement.dataset.theme).toBe("dark");

    await userEvent.click(within(wide).getByRole("button", { name: "Memory" }));
    const slider = screen.getAllByLabelText(/Target recall/)[0];
    fireEvent.change(slider, { target: { value: "0.8" } });
    expect(screen.getAllByText("Target recall: 80%")[0]).toBeInTheDocument();
    expect(window.localStorage.getItem("quillfin.retention")).toBe("0.8");
  });
});

test("Dialog opens and closes", () => {
  const onClose = vi.fn();
  const { rerender } = render(
    <Dialog open title="Hello" onClose={onClose}>
      body
    </Dialog>,
  );
  expect(screen.getByText("body")).toBeInTheDocument();
  rerender(
    <Dialog open={false} title="Hello" onClose={onClose}>
      body
    </Dialog>,
  );
  act(() => {});
  expect(screen.queryByText("body")).not.toBeInTheDocument();
});
