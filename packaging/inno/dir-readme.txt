First stop: pick where I live on this PC.

Metra install destination

Select the Metra product folder - the directory where metra.ps1 will live.

Examples:
  C:\Projects\_metra
  C:\Users\<you>\Documents\Metra

Do not select the portfolio parent (for example C:\Projects). That folder holds
sibling projects such as TicketTracker; Metra itself must be a separate product folder.

The path you choose is the install root. Metra does not append an extra \Metra folder.

If this folder is already a git clone of Metra, the installer replaces product files.
Developer checkouts can keep using git pull instead of the installer update button.
