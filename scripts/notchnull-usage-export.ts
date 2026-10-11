import { mkdirSync, writeFileSync, renameSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

export default {
  name: 'notchnull-usage-export',
  tui(api) {
    const directory = join(homedir(), 'Library', 'Application Support', 'NotchNull');
    const target = join(directory, 'mendcode-usage.json');
    let previous = '';
    const publish = () => {
      try {
        const quota = api.usage().quota.filter(q => q.provider === 'claude').map(q => ({
          provider: q.provider, window: q.window, usedPercent: q.usedPercent,
          resetsAt: q.resetsAt, observedAt: q.observedAt
        }));
        const content = JSON.stringify({version: 1, source: 'mendcode', quota});
        if (content === previous) return;
        mkdirSync(directory, { recursive: true, mode: 0o700 });
        const temporary = target + '.' + process.pid + '.tmp';
        writeFileSync(temporary, content, { mode: 0o600 });
        renameSync(temporary, target);
        previous = content;
      } catch { /* Preserve the last atomic snapshot; NotchNull checks its age. */ }
    };
    publish();
    const timer = setInterval(publish, 10000);
    api.onDispose(() => clearInterval(timer));
  }
};
