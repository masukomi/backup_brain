## v2.1.0 


### Changed 

-   consolidated colors used to have a consistent 6 color color palette


### Fixed 

-   corrected syntax error in run_me_first.sh


## v2.0.0 


### Added 

-   docker suport
-   `run_me_first.sh` script to ease initial setup
-   added automated backups for docker users


### Changed 

-   changed bookmarklet description &amp; text in footer
-   silenced a "whiny" rails log warning
-   upgraded version of mongodb\\_meilisearch
-   modified export &amp; import scripts to run
    inside or outside of docker


### Fixed 

-   handling of Meilisearch API Key Errors


## v1.2.0 


### Added 

-   If the system failed in an attempt to archive a page, it will now show
    an error code indicating _why_ the attempt failed.


### Fixed 

-   When multiple archives were present for the same bookmark, the text displayed, and passed to the search engine, were from the oldest, not newest archive.
-   Corrected test for which Archived / Archiving icon and link to show in the bookmark list.
-   Pages with invalid text encoding are now archived gracefully instead of causing the archive to fail. Any invalidly encoded characters are now removed.


## v1.1.0 


### Added 

-   Web based bookmark importer
-   Support for importing HTML bookmarks
-   A Bookmarklet
    See [the Helpers documentation](https://backupbrain.app/helpers/) for more details.


### Changed 

-   tags imported from Pinboard will now be downcased
-   The success page used by the bookmark &amp; extensions
    will now close itself. This helps when using the Bookmarklet.


### Fixed 

-   Deleting a bookmark no longer makes you loose your place in the list
