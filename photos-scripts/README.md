# Photos scripts

This folder contains small utility scripts for organizing and cleaning up photo libraries.

## photos-organize.sh

Organizes image files in a chosen folder into a date-based folder structure.

- Reads EXIF metadata with `exiftool` to get the original capture date
- Falls back to the file modification date if EXIF date is unavailable
- Creates folders by year and then by full date
- Optionally includes a location summary (city/country) in the folder name when available
- Moves supported files such as JPG, JPEG, HEIC, PNG, and MOV into the target structure

Usage:

```bash
./photos-organize.sh /path/to/photos
```

## reformat-folder-names.sh

Normalizes existing folder names that follow common photo-import naming patterns.

- Detects names like `Something, 12 July 2024`
- Handles optional punctuation such as a trailing period after the day number
- Rewrites them into a consistent format for easier sorting and automated processing
- Useful before or after organizing a photo library

Usage:

```bash
./reformat-folder-names.sh /path/to/photos
```
