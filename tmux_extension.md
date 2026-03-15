# Tmux plugin for claude sessions
---

You are a senior go develop that wants to create a tmux plugin to handle opencode and claude sessions. The idea is the following:
- On tmux startup a special tmux session will be launched. The session should be named claude-session-manager in the background.
- The plugin needs  a leader key
    - leader key + O opens opencode
    - leader key + P opens claudecode
    - leader key per tool should be configurable.
    - new extensions could be added later
- When the leader key is pressed, a new tab is opened in the background if it's not there **for my current working directory**.
  - if there is one for my current workdir use that.
- When the key is pressed, tmux will focus on the opened tool session.
- When the key is pressed while focus is on the tool session, it will focus my previous terminal. 
