# BackupBrain
BackupBrain is a self-hosted single-user bookmarking app that automatically creates local text-only archives of whatever you bookmark.

Over time the things it can ingest for you will expand to include "Bookmarked" posts on Mastodon

A list of all your bookmarks…

![screenshot of bookmarks list](https://github.com/masukomi/backup_brain/blob/graphical_resources/screenshots/list_screenshot@2x.png?raw=true)

Text Archives of each one…

![screenshot of archive](https://github.com/masukomi/backup_brain/blob/graphical_resources/screenshots/archive_screenshot@2x.png?raw=true)


This project is still new, and as such there's no one-click installation. It requires executing a series of commands in the terminal. They're well documented though, so as long as you can open a terminal and `cd` to a directory, you should be fine.


<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [BackupBrain](#backupbrain)
    - [Warning / Disclaimer & Privacy](#warning--disclaimer--privacy)
    - [Data Security](#data-security)
    - [Your Privacy](#your-privacy)
    - [Goals & Uses](#goals--uses)
- [Usage](#usage)
    - [Adding Bookmarks](#adding-bookmarks)
    - [In the web page](#in-the-web-page)
    - [Via Browser Extensions](#via-browser-extensions)
    - [Archives](#archives)
    - [Importing from Pinboard.in](#importing-from-pinboardin)
    - [Search](#search)
- [Setup](#setup)
    - [Homebrew (for mac folks)](#homebrew-for-mac-folks)
    - [Ruby](#ruby)
    - [rbenv Installation](#rbenv-installation)
    - [rbenv Setup](#rbenv-setup)
    - [MongoDB](#mongodb)
    - [Local installation](#local-installation)
    - [Meilisearch](#meilisearch)
    - [Domain Name](#domain-name)
    - [Ruby On Rails](#ruby-on-rails)
    - [Starting the Server](#starting-the-server)
    - [You Did It!](#you-did-it)

<!-- markdown-toc end -->


# Warning / Disclaimer & Privacy

## Data Security
Bookmarks are _public_ by default. This is so that you can - for example - share a link to bookmarks tagged with "dogs" or to an archive of a web page that no longer exists. Bookmarks marked "Private" are only visible _to you_ after logging in.

Bookmarks and archives are not encrypted, but your password is. 

BackupBrain works like most of the apps that you run locally on your computer. Anyone who has access to your computer can, for example, open your text editor, and create and edit files on your computer. People who can't access your computer, can't. The same applies to the database and search engine it uses. 

See the [Backups](#backups) section for how to preserve your data in case your computer catches fire… or whatever.

## Your Privacy
BackupBrain has no tracking code, and doesn't share data with anyone. We do however get the little icons for your bookmarks from google. So, they will see a request for the domain name for each site you have bookmarked, and bring up in the browser. There is [a ticket](https://github.com/masukomi/backup_brain/issues/26) to disable this behavior in a future version. 

There is no tracking information whatsoever. The source code is _always_ auditable, and I will _always_ try and be clear about what's in every new version. 

# Goals & Uses

I want BackupBrain to store anything you find useful in your online journeys. However, it will only ever gather information that you explicitly tell it to. I'm starting with bookmarks. 

# Usage
After you've [set up the system](#setup), it's time to give it some data to work with.

run `./serve` if you haven't already, and load it up in your browser. By default this is at `http://127.0.0.1:3333`, but setup discusses ways to give it a nicer domain name.

Next, create an account by clicking the "Create an Account" link in the right sidebar. This asks for an email, username but _will not send a confirmation email_. It's your instance. If you want to use a fake email, no-one's going to stop you. 

## Adding Bookmarks 
### In the web page
There's an "Add a Bookmark" link at the top of the right sidebar. Click it. Fill in the resulting form, and submit it.

This is a bookmarking app. There's not much to it. 😉

### Via Browser Extensions

There's a browser extension that's been tested with Firefox. 
**FINISH ME - LINK TO EXTENSION**

### Archives
The system will automatically attempt to create a local archive of the web page. Whenever there's a list of bookmarks you'll see an "Archived" link in each row, just above the "edit". If you see a cloud download icon, then it wasn't able to archived it. Click that to have it try again. 

Clicking "Archived" will bring up the archived version of the web page. 

Notes:

1. It currently won't be able to archive pages that require a user to be logged in to be viewed.
2. Archived text is not _yet_ being indexed by the search engine. 
  There's [an open ticket](https://github.com/masukomi/backup_brain/issues/27) to address that.

### Importing from Pinboard.in
⚠ If you've got thousands of bookmarks this can take _hours_. On my computer it's This is because it's not parallelized _yet_ and it's creating an archive for every page it can. 

There is no danger to running this process multiple times. If your import includes a bookmark it already knows about, it'll just update its information with the data from the file.

1. Log in to Pinboard. 
2. Click "settings" in the top navigation bar.
3. Click the "backup" tab.
5. Click the link that says "➔ JSON"
   It'll generate and download a JSON file of your bookmarks.
6. Open up the terminal and `cd` to wherever you cloned the repo.
   Note: there's [an open ticket](https://github.com/masukomi/backup_brain/issues/23) to let you
   import this via the web page. 
7. Move or copy your exported JSON to the current directory.
8. Run the following command after replacing `pinboard_export.json` with the name of your file.
   ⚠ Note that there are NO spaces between the comma and the 0.
   `bundle exec rake importer:pinboard_import[pinboard_export.json,0]`
9. Do not close the terminal window. Leave it open until it finishes and you see a message claiming it `Successfully imported: <numberhere> bookmarks.`
   If you need to put your laptop to sleep or close its lid that's fine. It'll keep going when you wake it back up again. 
10. If something goes wrong along the way you can skip an initial number of records by rerunning it and changing that 0 to the number of the 1st record you want to start processing.



## Search
The search engine allows full text search of the title, url, description, and tags of every Bookmark. Leave it on "Best Match" to have results shown in the order of the best match. "Newest"
 will, unsurprisingly, sort by the age of the bookmark, with the newest ones shown first.

 
There's [an open ticket](https://github.com/masukomi/backup_brain/issues/27) to include archives in the searches.


# Setup
Unless stated otherwise, you should run the specified commands in the terminal, and from within the directory you cloned BackupBrain into.

All instructions assume you're going to be running this on the same computer you're using. 

## Homebrew (for mac folks)

There's a good chance you've already got it installed, but if not [go to brew.sh](https://brew.sh/) and follow the instructions. It's the most popular package manager for developer stuff on macOS.

## Ruby
We're using Ruby 3.x. macOS ships with an _ancient_ version of Ruby, and most other OSs don't tend to try and keep this up to date either.

If you're not a Ruby developer, here's how to get that. Ruby devs can skip to the next section.

If you're already an [ASDF](https://asdf-vm.com/) user though, go ahead and use that instead of `rbenv` to configure Ruby. There's a `.tool-versions` file for you.

**Everyone else**: I'm going to recommend you use [rbenv](https://github.com/rbenv/rbenv). 

Once you've set up `rbenv` your terminal environment will read the `.ruby-version` file and switch to the appropriate version of Ruby every time you `cd` into the BackupBrain directory.

### rbenv Installation 
**macOS**

``` shell
brew install rbenv ruby-build
```

**Debian flavored things**

``` shell
sudo apt install rbenv
```
### rbenv Setup

``` shell
rbenv init
```
It'll be wired up the next time you open a new terminal window, so open a new window `cd` into the BackupBrain home directory.

First, make sure the version mentioned in this README isn't out of date.

``` shell
cat .ruby-version
```
Now, install whatever version number that said. Like this:

``` shell
rbenv install 3.2.0
```

Now `cd` to another directory (`cd ../` is fine), then `cd` back to your `backup_brain` directory, and run `ruby --version` it should output a version that matches whatever was in the `.ruby-version` file.

If we bump the required version of Ruby in the future `rbenv` will let you know when you `cd` into it. Then you just run `rbenv install <whatever version it tells you>`. You probably saw that message when you `cd`'d into this directory after installing `rbenv`.


## MongoDB
Install it locally, or set up a [MongoDB cloud instance](https://www.mongodb.com/). The free tier should be more than enough.

### Local installation

**macOS**
``` shell
# install it
brew info mongodb-community
# start it running in the background
brew services start mongodb/brew/mongodb-community
```

**everything else**
I have no idea. [The official website](https://www.mongodb.com/) is where I'd start. Once you figure it out, please file a ticket with the information, or make a Pull Request to fix it.

## Meilisearch
Our full text search is powered by [Meilisearch](https://www.meilisearch.com). 

``` shell
# install it
brew install meilisearch
```

Run it once with no arguments & retrieve the `master-key` it generates for you.

``` shell
meilisearch
```
look for lines like this

```text
We generated a new secure master key for you (you can safely use this token):

>> --master-key PIYLd4loyTeAce4-Mr7rW5zLz3eLxk3RlQK-uQJdOjs <<

Restart Meilisearch with the argument above to use this new and secure master key.
```

Copy that master key. We're about to put it in a configuration file. Once you've got that copied, hit `^c` (control + c) to shut down the meilisearch server. Next time we start it that master key will be used.

Now, we're going to make a configuration file with your Meilisearch info, so that the library we're using to integrate with Meilisearch knows where to talk to. 

Copy the `.env.sample` file to `.env` You'll probably have to do this from the command line because most systems hide "dot files".  Run this to copy it.

``` shell
cp .env.sample .env
```

Now, open that new `.env` file in your favorite text editor.  E.g. run `code .env` in the terminal to open it up in VSCode. It should look like this. Paste in the master-key you got when you launched meilisearch directly after `MEILISEARCH_API_KEY=`. Save the file and close it out. 

```
HOST_NAME=localhost
PORT=3334
DELAYED_JOB_WORKERS=2
SEARCH_ENABLED=true
MEILISEARCH_API_KEY=
MEILISEARCH_URL=http://127.0.0.1:7700
MEILISEARCH_TIMEOUT=10
MEILISEARCH_MAX_RETRIES=2
```

### Domain Name
You'll probably be running this locally, but you can still have a pretty name.
Simply add a new line to your `/etc/hosts` file. You'll have to do this as root. For example `sudo code /etc/hosts` to open it in VSCode and then add the following line and save.

```text
127.0.0.1	backupbrain
```

Then replace `HOST_NAME=localhost` in your `.env` file (see above).

After you boot the app you'll be able to visit `http://backupbrain:3334` instead of `http://localhost:3334`

You can use anything you want in `/etc/hosts` as long as it's only one word. `bb` would be a nice and short domain name.

### Ruby On Rails
This presumes you've got Ruby 3.x or newer installed (see above).

1. install libraries
   in console: run `bundle install`
2. Double check the MongoDB configuration file
   The `config/mongoid.yml` controls how Rails talks to MongoDB. I've given you a default file that should "just work" _if you've got a MongoDB installation running on the same computer_. You do if you followed the instructions above. If you've installed it elsewhere I'm going to assume you know how to tweak this configuration accordingly.
3. in console: boot the server by running `./serve`
  - This also checks if meilisearch is running, and starts it if needed.


## Delayed Job
Delayed Job handles tasks in the background for us. Before we can use it we need to configure a place in the database to store queued Jobs for it to work on. 

``` bash
rails runner 'Delayed::Backend::Mongoid::Job.create_indexes'
```

The `serve` script will take care of starting the appropriate number of background worker processes & killing them when it's closed. 

⚠ This will kill ALL delayed job workers, even ones from other tasks. The default tool for stopping processes isn't working.

### Starting the Server

Run `./serve` in the root of the project. It'll make sure meilisearch is running and start it if it isn't, and then start the Rails server. It assumes MongoDB is already running the background.

Note: the `serve` script reads the port number from your `.env`. This defaults to `3334` so as not to conflict with the commonly used port `3000`. Feel free to change this in your `.env` if you need to. 

### You Did It!
_THAT'S IT._ Everything's installed. Sorry it was so much manual geekery. I will improve this before the general release. 

Now it's time to actually _use_ what you've set up. Head back to [Usage](#usage). 

## Backing Up Data
I don't have your data, so I can't back it up for you.

In the `scripts` directory you'll find an export and import script. I'd recommend setting up a cron job to run the `export` script a couple times a day. It'll create a `mongo_exports` directory, and save a file for each data type. Running the import script on a fresh database will load all of them from the last backup. 

⚠️ Running the import script on an _existing_ database will _delete and replace_ the existing data.

_Make sure these files are being backed up to another computer in case yours dies 🔥._

NOTE: these scripts use the `MONGODB_URI` and `DATABASE_NAME` environment variables. If you don't set those, then it'll assume you haven't changed the database name, and that it's running on localhost. If your MongoDB installation is on a different server from your BackupBrain then you'll need to set the `MONGODB_URI` according to the [connection string documentation](https://www.mongodb.com/docs/manual/reference/connection-string/). This can be set in the environment or you can just hardcode it into the scripts.



### Example Backup using Cron
Here's an example cronjob that will

- cd into the directory where I cloned devgood on my computer
- run the export script
- send its output to `log/cron.log`  (overwriting output from the last run)

``` cron
0 * * * * /bin/bash -l -c 'cd ~/workspace/devgood && ./scripts/export.sh > ~/workspace/backup_brain/log/cron.log 2>&1'
```

See [this post about using cron](https://www.howtogeek.com/devops/what-is-a-cron-job-and-how-do-you-use-them/) if you're unfamiliar. Note that cron's default editor is Vim, but that page includes instructions on how to edit your crontab (list of cron jobs) without using Vim. 

Assuming your computer has automatic backups running, these files should get included. 
