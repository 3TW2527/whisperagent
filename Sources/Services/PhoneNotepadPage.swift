import Foundation

/// The page the phone opens from the QR code: pick a meeting, jot notes and actions, send photos, tick off
/// actions. Entries wait on the phone while the connection is down and are sent when it's back.
enum PhoneNotepadPage {
    static let expiredHTML = #"""
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Link expired</title>
    <style>
    body { margin: 0; padding: 48px 24px; font: 17px/1.5 -apple-system, system-ui, sans-serif; background: #f6f6f4; color: #1c1c1e; text-align: center; }
    @media (prefers-color-scheme: dark) { body { background: #111113; color: #f2f2f7; } }
    </style></head>
    <body><h2>This link has expired</h2><p>The phone notepad was turned off or restarted. Turn it on in WhisperLectures and scan the new QR code.</p></body></html>
    """#

    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="color-scheme" content="light dark">
    <title>Notepad</title>
    <style>
    :root { --bg: #f6f6f4; --card: #ffffff; --text: #1c1c1e; --muted: #6e6e73; --line: #e2e2de; --accent: #0a6cdf; --ok: #2f9e4f; --warn: #c26a00; --bad: #d1352b; }
    @media (prefers-color-scheme: dark) { :root { --bg: #111113; --card: #1d1d20; --text: #f2f2f7; --muted: #9a9aa1; --line: #2e2e33; --accent: #4c9dff; --ok: #3fbf62; --warn: #e89a2c; --bad: #ff6159; } }
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.45 -apple-system, system-ui, sans-serif; }
    header { position: sticky; top: 0; z-index: 2; background: var(--bg); padding: calc(env(safe-area-inset-top) + 10px) 16px 10px; border-bottom: 1px solid var(--line); }
    .row { display: flex; gap: 8px; align-items: center; }
    select, button, textarea, input { font: inherit; color: inherit; }
    select, input[type=text] { flex: 1; min-width: 0; padding: 9px 10px; border-radius: 10px; border: 1px solid var(--line); background: var(--card); }
    button { border-radius: 10px; padding: 9px 12px; background: var(--card); border: 1px solid var(--line); white-space: nowrap; }
    button.primary { background: var(--accent); border-color: var(--accent); color: #fff; font-weight: 600; }
    button:disabled { opacity: .45; }
    .status { margin-top: 8px; font-size: 13px; color: var(--muted); display: flex; gap: 6px; align-items: center; }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--muted); flex: none; }
    .dot.on { background: var(--ok); } .dot.off { background: var(--bad); } .dot.wait { background: var(--warn); }
    .tabs { display: flex; gap: 6px; margin-top: 10px; }
    .tabs button { flex: 1; padding: 7px; font-size: 15px; }
    .tabs button.sel { background: var(--text); color: var(--bg); border-color: var(--text); }
    .panel { margin-top: 10px; display: none; gap: 8px; flex-direction: column; }
    .panel.show { display: flex; }
    main { padding: 12px 16px 170px; }
    .entry { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 10px 12px; margin-bottom: 8px; white-space: pre-wrap; overflow-wrap: anywhere; }
    .entry.pending { border-style: dashed; opacity: .7; }
    .entry .time { color: var(--muted); font-size: 13px; font-variant-numeric: tabular-nums; margin-right: 6px; }
    .entry.heading { background: none; border: 0; padding: 6px 2px 2px; font-weight: 600; color: var(--muted); }
    .entry.todo::before { content: "☐ "; } .entry.done::before { content: "☑ "; } .entry.done { color: var(--muted); text-decoration: line-through; }
    .action { display: flex; gap: 12px; align-items: flex-start; }
    .action input { width: 24px; height: 24px; flex: none; margin: 0; accent-color: var(--ok); }
    .action .meta { display: block; font-size: 13px; color: var(--muted); }
    .action .meta.overdue { color: var(--bad); }
    .empty { color: var(--muted); text-align: center; padding: 36px 8px; }
    .note-name { font-size: 12px; color: var(--muted); margin: 0 0 10px; }
    footer { position: fixed; left: 0; right: 0; bottom: 0; z-index: 2; background: var(--bg); border-top: 1px solid var(--line); padding: 8px 12px calc(env(safe-area-inset-bottom) + 8px); }
    textarea { display: block; width: 100%; min-height: 46px; max-height: 38vh; resize: none; padding: 11px 12px; border-radius: 12px; border: 1px solid var(--line); background: var(--card); }
    .tools { display: flex; gap: 8px; margin-top: 8px; }
    .tools .grow { flex: 1; }
    .toggle.on { background: var(--warn); border-color: var(--warn); color: #fff; }
    .banner { margin: 0 0 10px; padding: 10px 12px; border-radius: 12px; background: var(--card); border: 1px solid var(--line); font-size: 14px; }
    .hidden { display: none !important; }
    </style>
    </head>
    <body>
    <header>
      <div class="row">
        <select id="course" aria-label="Project or course"></select>
      </div>
      <div class="row" style="margin-top:8px">
        <select id="meeting" aria-label="Meeting"></select>
        <button id="newMeetingButton" aria-label="New meeting">＋</button>
      </div>
      <div class="panel" id="newMeetingPanel">
        <div class="row">
          <select id="newSeries" aria-label="Series"></select>
          <input type="text" id="newTitle" placeholder="Title (optional)">
        </div>
        <div class="row">
          <button id="cancelNew" style="flex:1">Cancel</button>
          <button id="createNew" class="primary" style="flex:2">Create, starting now</button>
        </div>
      </div>
      <div class="tabs">
        <button id="tabNotes" class="sel">Notes</button>
        <button id="tabActions">Actions</button>
      </div>
      <div class="status"><span class="dot" id="dot"></span><span id="statusText">Connecting…</span></div>
    </header>

    <main>
      <div id="notesView">
        <p class="note-name" id="noteName"></p>
        <div id="feed"></div>
      </div>
      <div id="actionsView" class="hidden"></div>
    </main>

    <footer id="composer">
      <textarea id="text" rows="1" placeholder="Note something…" enterkeyhint="send"></textarea>
      <div class="tools">
        <button id="actionToggle" class="toggle" aria-pressed="false">☐ Action</button>
        <button id="photoButton">Photo</button>
        <input type="file" id="photoInput" accept="image/*" multiple class="hidden">
        <span class="grow"></span>
        <button id="send" class="primary">Add</button>
      </div>
    </footer>

    <script>
    (function () {
      const token = new URLSearchParams(location.search).get("t") || "";
      const $ = id => document.getElementById(id);
      const store = {
        get(key, fallback) { try { const v = localStorage.getItem("wl_" + key); return v ? JSON.parse(v) : fallback; } catch (e) { return fallback; } },
        set(key, value) { try { localStorage.setItem("wl_" + key, JSON.stringify(value)); } catch (e) {} }
      };
      const esc = s => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
      const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);

      let courses = [];
      let macName = "your Mac";
      let courseId = store.get("course", null);
      let meetingNumber = store.get("meeting", null);
      let tab = "notes";
      let isAction = false;
      let queue = store.get("queue", []);   // text entries waiting to be sent: { id, course, meeting, text, kind, time }
      let photos = [];                      // photos waiting to be sent (kept in memory only)
      let connection = "connecting";        // connecting | on | off | expired
      let flushing = false;
      let noteText = "";

      async function api(path, options) {
        options = options || {};
        const headers = Object.assign({ "X-Token": token }, options.headers || {});
        const response = await fetch(path, Object.assign({}, options, { headers }));
        if (response.status === 403) { connection = "expired"; renderStatus(); throw new Error("expired"); }
        const type = response.headers.get("content-type") || "";
        const data = type.includes("json") ? await response.json() : await response.text();
        if (!response.ok) { const error = new Error((data && data.error) || "Request failed"); error.status = response.status; throw error; }
        return data;
      }

      const course = () => courses.find(c => c.id === courseId);
      const meeting = () => { const c = course(); return c && c.meetings.find(m => m.number === meetingNumber); };

      // ---- State ----

      async function loadState() {
        try {
          const state = await api("/api/state");
          courses = state.courses;
          macName = state.mac || macName;
          connection = "on";
          if (!course()) courseId = courses.length ? courses[0].id : null;
          const c = course();
          if (c && !meeting()) meetingNumber = c.current || (c.meetings[0] && c.meetings[0].number) || null;
          remember();
          renderPickers();
          renderStatus();
          await refresh();
        } catch (e) {
          if (connection !== "expired") connection = "off";
          renderStatus();
        }
      }

      function remember() { store.set("course", courseId); store.set("meeting", meetingNumber); }

      async function refresh() {
        const c = course();
        if (!c) { renderFeed(); return; }
        try {
          if (tab === "notes" && meeting()) {
            const note = await api("/api/note?course=" + encodeURIComponent(c.id) + "&meeting=" + meetingNumber);
            noteText = note.content;
            $("noteName").textContent = "Saving to " + note.name;
          }
          if (tab === "actions") await refreshActions();
          connection = "on";
        } catch (e) {
          if (connection !== "expired") connection = "off";
        }
        renderFeed();
        renderStatus();
      }

      // ---- Sending ----

      function add() {
        const text = $("text").value.trim();
        if (!text) return;
        if (!meeting()) { alert("Pick or create a " + unitName().toLowerCase() + " first."); return; }
        queue.push({ id: uid(), course: courseId, meeting: meetingNumber, text, kind: isAction ? "action" : "note", time: new Date().toISOString() });
        store.set("queue", queue);
        $("text").value = "";
        autosize();
        if (isAction) setAction(false);
        renderFeed();
        flush();
      }

      async function flush() {
        if (flushing) return;
        flushing = true;
        try {
          while (queue.length) {
            const entry = queue[0];
            try {
              await api("/api/entry", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(entry) });
            } catch (e) {
              if (e.status === 404 || e.status === 400) { queue.shift(); store.set("queue", queue); continue; }  // meeting deleted: drop it
              throw e;
            }
            queue.shift();
            store.set("queue", queue);
          }
          while (photos.length) {
            const photo = photos[0];
            await api("/api/photo?course=" + encodeURIComponent(photo.course) + "&meeting=" + photo.meeting + "&name=" + encodeURIComponent(photo.file.name || "photo.jpg"),
                      { method: "POST", headers: { "Content-Type": photo.file.type || "image/jpeg" }, body: photo.file });
            photos.shift();
          }
          connection = "on";
          await refresh();
        } catch (e) {
          if (connection !== "expired") connection = "off";
        }
        flushing = false;
        renderFeed();
        renderStatus();
      }

      // ---- Meetings ----

      function unitName() { const c = course(); return c ? c.unit : "Meeting"; }

      async function createMeeting() {
        const c = course();
        if (!c) return;
        $("createNew").disabled = true;
        try {
          const result = await api("/api/meeting", { method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ course: c.id, series: $("newSeries").value, title: $("newTitle").value.trim() }) });
          meetingNumber = result.number;
          remember();
          $("newTitle").value = "";
          showNewMeeting(false);
          await loadState();
        } catch (e) {
          alert(e.message === "expired" ? "This link has expired." : "Couldn't create it: " + e.message);
        }
        $("createNew").disabled = false;
      }

      function showNewMeeting(show) {
        $("newMeetingPanel").classList.toggle("show", show);
        const c = course();
        const series = c ? c.series : [];
        $("newSeries").innerHTML = '<option value="">No series</option>' + series.map(s => '<option value="' + esc(s) + '">' + esc(s) + "</option>").join("");
        $("newSeries").classList.toggle("hidden", !series.length);
        $("createNew").textContent = "Create " + unitName().toLowerCase() + ", starting now";
      }

      // ---- Actions ----

      let actions = [];
      async function refreshActions() {
        const c = course();
        if (!c || !c.isProject) { actions = []; return; }
        actions = (await api("/api/actions?course=" + encodeURIComponent(c.id))).actions;
      }

      async function tick(id, box) {
        box.disabled = true;
        try {
          await api("/api/action", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ course: courseId, id, done: true }) });
          actions = actions.filter(a => a.id !== id);
          renderFeed();
        } catch (e) {
          box.checked = false;
          box.disabled = false;
          alert(e.message);
          refresh();
        }
      }

      // ---- Rendering ----

      function renderPickers() {
        $("course").innerHTML = courses.map(c => '<option value="' + esc(c.id) + '">' + esc(c.name) + "</option>").join("");
        $("course").value = courseId || "";
        $("course").parentElement.classList.toggle("hidden", courses.length < 2);
        const c = course();
        const meetings = c ? c.meetings : [];
        $("meeting").innerHTML = meetings.length
          ? meetings.map(m => {
              const date = new Date(m.date).toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
              return '<option value="' + m.number + '">' + esc(m.label + " · " + m.title + " · " + date) + "</option>";
            }).join("")
          : '<option value="">No ' + esc(unitName().toLowerCase()) + "s yet: tap ＋</option>";
        $("meeting").value = meetingNumber || "";
        $("tabActions").classList.toggle("hidden", !(c && c.isProject));
        $("newMeetingButton").setAttribute("aria-label", "New " + unitName().toLowerCase());
      }

      function renderStatus() {
        const dot = $("dot");
        const waiting = queue.length + photos.length;
        dot.className = "dot " + ({ on: waiting ? "wait" : "on", off: "off", expired: "off", connecting: "" }[connection] || "");
        let text;
        if (connection === "expired") text = "Link expired: turn the notepad on in WhisperLectures and scan the new QR code.";
        else if (connection === "off") text = "Can't reach " + macName + (waiting ? " · " + waiting + " waiting, sent when it's back" : "") + ".";
        else if (connection === "connecting") text = "Connecting…";
        else text = waiting ? "Sending " + waiting + "…" : "Connected to " + macName;
        $("statusText").textContent = text;
      }

      function renderFeed() {
        $("notesView").classList.toggle("hidden", tab !== "notes");
        $("actionsView").classList.toggle("hidden", tab !== "actions");
        $("composer").classList.toggle("hidden", tab !== "notes");
        if (tab === "actions") { renderActions(); return; }

        const feed = $("feed");
        const blocks = [];
        // Lines of the phone note, with indented continuation lines kept with their entry.
        for (const line of noteText.split("\n")) {
          if (/^\s{2,}\S/.test(line) && blocks.length) { blocks[blocks.length - 1].text += "\n" + line.trim(); continue; }
          if (!line.trim() || /^# /.test(line)) continue;
          blocks.push({ text: line });
        }
        let html = blocks.map(b => {
          const t = b.text;
          let m;
          if ((m = /^\s*[-*+] \[( |x|X)\] (.*)$/s.exec(t))) return '<div class="entry ' + (m[1] === " " ? "todo" : "done") + '">' + esc(m[2]) + "</div>";
          if ((m = /^\s*[-*+] (\d{1,2}:\d{2}) (.*)$/s.exec(t))) return '<div class="entry"><span class="time">' + m[1] + "</span>" + esc(m[2]) + "</div>";
          if ((m = /^#{2,6} (.*)$/.exec(t))) return '<div class="entry heading">' + esc(m[1]) + "</div>";
          return '<div class="entry">' + esc(t.replace(/^\s*[-*+] /, "")) + "</div>";
        }).join("");
        const pending = queue.filter(q => q.course === courseId && q.meeting === meetingNumber);
        html += pending.map(q => '<div class="entry pending' + (q.kind === "action" ? " todo" : "") + '">' + esc(q.text) + "</div>").join("");
        html += photos.filter(p => p.course === courseId && p.meeting === meetingNumber).map(p => '<div class="entry pending">Photo: ' + esc(p.file.name || "photo") + "</div>").join("");
        if (!html) {
          html = meeting()
            ? '<div class="empty">Nothing here yet. Notes you add go into this ' + esc(unitName().toLowerCase()) + "'s phone note on " + esc(macName) + ".</div>"
            : '<div class="empty">Pick a ' + esc(unitName().toLowerCase()) + " above, or tap ＋ to start one now.</div>";
        }
        const atBottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 40;
        feed.innerHTML = html;
        if (atBottom) window.scrollTo(0, document.body.scrollHeight);
      }

      function renderActions() {
        const view = $("actionsView");
        if (!actions.length) { view.innerHTML = '<div class="empty">No open actions. Add one from Notes with ☐ Action.</div>'; return; }
        view.innerHTML = actions.map(a =>
          '<label class="entry action"><input type="checkbox" data-id="' + esc(a.id) + '"><span>' + esc(a.text) +
          '<span class="meta' + (a.overdue ? " overdue" : "") + '">' + esc([a.meeting, a.due ? "due " + a.due : ""].filter(Boolean).join(" · ")) + "</span></span></label>"
        ).join("");
        view.querySelectorAll("input[type=checkbox]").forEach(box => box.addEventListener("change", () => tick(box.dataset.id, box)));
      }

      function setAction(on) {
        isAction = on;
        $("actionToggle").classList.toggle("on", on);
        $("actionToggle").setAttribute("aria-pressed", String(on));
        $("text").placeholder = on ? "Something to do…" : "Note something…";
      }

      function autosize() {
        const area = $("text");
        area.style.height = "auto";
        area.style.height = Math.min(area.scrollHeight, window.innerHeight * 0.38) + "px";
      }

      // ---- Events ----

      $("course").addEventListener("change", e => {
        courseId = e.target.value;
        const c = course();
        meetingNumber = c ? (c.current || (c.meetings[0] && c.meetings[0].number) || null) : null;
        if (!(c && c.isProject) && tab === "actions") tab = "notes";
        remember(); renderPickers(); noteText = ""; refresh();
      });
      $("meeting").addEventListener("change", e => { meetingNumber = Number(e.target.value) || null; remember(); noteText = ""; refresh(); });
      $("newMeetingButton").addEventListener("click", () => showNewMeeting(!$("newMeetingPanel").classList.contains("show")));
      $("cancelNew").addEventListener("click", () => showNewMeeting(false));
      $("createNew").addEventListener("click", createMeeting);
      $("tabNotes").addEventListener("click", () => { tab = "notes"; $("tabNotes").classList.add("sel"); $("tabActions").classList.remove("sel"); refresh(); });
      $("tabActions").addEventListener("click", () => { tab = "actions"; $("tabActions").classList.add("sel"); $("tabNotes").classList.remove("sel"); refresh(); });
      $("actionToggle").addEventListener("click", () => setAction(!isAction));
      $("send").addEventListener("click", add);
      $("text").addEventListener("input", autosize);
      $("text").addEventListener("keydown", e => { if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); add(); } });
      $("photoButton").addEventListener("click", () => {
        if (!meeting()) { alert("Pick or create a " + unitName().toLowerCase() + " first."); return; }
        $("photoInput").click();
      });
      $("photoInput").addEventListener("change", e => {
        for (const file of e.target.files) photos.push({ course: courseId, meeting: meetingNumber, file });
        e.target.value = "";
        renderFeed();
        flush();
      });
      document.addEventListener("visibilitychange", () => { if (!document.hidden) { flush(); loadState(); } });
      window.addEventListener("online", flush);

      setInterval(() => {
        if (document.hidden || connection === "expired") return;
        if (queue.length || photos.length) flush(); else refresh();
      }, 5000);

      loadState().then(flush);
    })();
    </script>
    </body>
    </html>
    """#
}
