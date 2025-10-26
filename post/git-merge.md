---
title: "Why I prefer git merge over rebase"
date: 2025-10-26
---

- A merge commit records the true integration point of two branches. When rebasing, the integration of the branch gets sneaked into the commits as if you were integrating all along, but you were not. When your integration step goes wrong, it's easy to catch with a merge commit.
- When in git, don't try to erase commits and branches. When a team uses git, it's never a single linear history.
- Resolve conflicts ONCE. The merge process is easier and hard to screw up.
- If you like rebasing so you can remove your WIP commits, please don't. WIP commits are OK. The more commits you have, the better, because commit messages are like logs. When debugging, I'd rather have DEBUG level logs than INFO level logs.
- If you're worried about readability of git log, just use a git alias that gives you a pretty view of the history. Here's one you can use (replace YOUR_ORG/YOUR_REPO with your github repo):

<img src="/images/gitprlog.png" alt="Screenshot of git prlog alias output" loading="lazy">

```bash
git log main --first-parent --merges --grep='^Merge pull request' \
  --pretty='%h|%ad|%an|%s|%b' --date=short "$@" |
awk -F'|' -v repo='https://github.com/YOUR_ORG/YOUR_REPO/pull/' '
BEGIN {
  # OSC 8 hyperlink open/close parts
  HOPEN = sprintf("%c",27) "]8;;";  BEL = sprintf("%c",7);  HCLOSE = HOPEN BEL;

  # Colors (works in most terminals + less -R)
  RST = sprintf("%c[0m",27);
  C_SHA = sprintf("%c[2m",27);      # faint
  C_DATE = sprintf("%c[2m",27);     # faint
  C_TITLE = sprintf("%c[1m",27);    # bold
  C_AUTH = sprintf("%c[36m",27);    # cyan
  C_LINK = sprintf("%c[34m",27);    # blue
}
{
  sha     = $1;
  date    = $2;
  author  = $3;
  subject = $4;
  body    = $5;

  gsub(/^[ \t]+|[ \t]+$/, "", body);
  title = (body != "" ? body : subject);

  # Extract PR number from subject: "Merge pull request #1234 ..."
  prnum = "";
  if (subject ~ /Merge pull request #[0-9]+/) {
    n = split(subject, parts, "#");
    if (n > 1) {
      prnum = parts[2];
      sub(/[^0-9].*$/, "", prnum);
    }
  }

  # Build clickable "(#1234)" with OSC-8; color the visible text blue
  pr = "";
  if (prnum != "") {
    url = repo prnum;
    pr  = HOPEN url BEL C_LINK "(#" prnum ")" RST HCLOSE;
  }

  # Colorize fields
  csha   = C_SHA sha RST;
  cdate  = C_DATE date RST;
  ctitle = C_TITLE title RST;
  cauth  = C_AUTH author RST;

  printf "%s  %s  %s  %s  %s\n", csha, cdate, ctitle, cauth, pr;
}' | ${PAGER:-less -R}

```

Here's how to create the alias:

```bash
git config --global alias.prlog \
'!f(){ git log main --first-parent --merges --grep="^Merge pull request" \
--pretty="%h|%ad|%an|%s|%b" --date=short "$@" | awk -F"|" -v repo="https://github.com/YOUR_ORG/YOUR_REPO/pull/" '"'"'BEGIN{HOPEN=sprintf("%c",27)"]8;;";BEL=sprintf("%c",7);HCLOSE=HOPEN BEL;RST=sprintf("%c[0m",27);C_SHA=sprintf("%c[2m",27);C_DATE=sprintf("%c[2m",27);C_TITLE=sprintf("%c[1m",27);C_AUTH=sprintf("%c[33m",27);C_LINK=sprintf("%c[34m",27);} {sha=$1;date=$2;author=$3;subject=$4;body=$5;gsub(/^[ \t]+|[ \t]+$/,"",body);title=(body!=""?body:subject);prnum="";if(subject~/Merge pull request #[0-9]+/){n=split(subject,parts,"#");if(n>1){prnum=parts[2];sub(/[^0-9].*$/,"",prnum);}}pr="";if(prnum!=""){url=repo prnum;pr=HOPEN url BEL C_LINK"(#"prnum")"RST HCLOSE;}csha=C_SHA sha RST;cdate=C_DATE date RST;ctitle=C_TITLE title RST;cauth=C_AUTH author RST;printf "%s  %s  %s  %s  %s\n",csha,cdate,ctitle,cauth,pr;}'"'"' | ${PAGER:-less -R}; }; f'

```
