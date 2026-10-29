# Notes for AI Coding Assistants

This repository is public.

## Examples must be generic

Placeholders, example text, doc comments, README examples, generated guide text (e.g. the `AGENTS.md` the app writes) and commit messages must not contain anything from a real user's courses, projects, meetings, people, documents, institution or files, even when such material was used to understand a feature. Invent a neutral example instead, for instance:

- Course: "Introduction to Algorithms", code `CS101`
- Project: "Capstone Project", code `CAP`
- Meeting series: "Team", Mondays at 10:00; untitled meetings are called "Team Meeting 2"
- Action: `- [ ] Draft the report due:2026-11-05`
- Key date: "Final presentation"

Test with throwaway data outside the repository, and never commit it.

Likewise, don't build one person's setup into the app: no special cases or recommendations for a particular product someone happens to use. Describe the general situation and mention specific products only as an example ("e.g.").
