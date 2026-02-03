# DocForge

DocForge is a lightweight documentation generator.

Documentation content is maintained in a structured Excel workbook and converted into readable HTML using PowerShell.  
The goal is to separate **content**, **structure**, and **presentation** while keeping the workflow simple and reproducible.

---

## Concept

- **Excel** is used as a structured content source  
- **PowerShell** generates the documentation  
- **HTML** is the output format  

This approach avoids classic Excel automation (VBA / Interop) and works without locking the source file.

---

## Project Structure

```text
DocForge/
├─ build/
│ └─ build-docs.ps1        # Documentation generator
├─ docs/
│ ├─ source/
│ │ ├─ docs.xlsx           # Example documentation source
│ │ └─ images/             # Shared image assets
│ ├─ out/
│ │ ├─ assets/             # Shared CSS/JS (Prism + DocForge)
│ │ ├─ images/             # Shared images (copied from source)
│ │ ├─ docs/               # Output per workbook
│ │ │ └─ index.html
│ │ └─ index.html          # Landing page
│ └─ assets/
│   ├─ prism.css
│   ├─ prism.js
│   ├─ docforge.css
│   └─ docforge.js
├─ README.md
```

---

## Excel Source Format

The Excel workbook contains a worksheet named **`Content`** with the following columns:

| Column    | Description                         |
|-----------|-------------------------------------|
| Chapter   | Main chapter (e.g. Git, PowerShell) |
| Section   | Section title within the chapter |
| Order     | Numeric order within a section |
| Type      | `text`, `code`, `note`, `image` |
| Lang      | Code language (`bash`, `powershell`, …) |
| Body      | Content text or code |
| Collapsed | `true` / `false` (render section as collapsible) |

---

## Build

From the repository root, run:

```powershell
.\build\build-docs.ps1
```

The script will:

- read the Excel workbook
- install required PowerShell modules if missing
- generate docs/out/index.html
- The Excel file can remain open while the build runs.

### Workbook selection

List publishable workbooks:

```powershell
.\build\build-docs.ps1 -ListWorkbooks
```

Build a specific workbook:

```powershell
.\build\build-docs.ps1 -Workbook docs.xlsx
```

By convention, workbooks containing _dev are ignored.

### Multi-workbook build

Build default workbook:

```powershell
.\build\build-docs.ps1
```

Build all publishable workbooks:

```powershell
.\build\build-docs.ps1 -All
```

List publishable workbooks:

```powershell
.\build\build-docs.ps1 -ListWorkbooks
```

Create portable zip packages:

```powershell
.\build\build-docs.ps1 -All -Package
```

Each package contains a complete, self-contained HTML documentation
including assets and images.
$OutDir
### Images

Image files are shared across all documentations.

Place image files in:
- docs/source/images/

In the workbook (Type = image), set Body to the filename only
(no paths, no subfolders), for example:
- git-branching.png

Images are copied automatically to the build output.

## Publishing Convention (Workbooks & HTML)

This repository distinguishes between **development** and **publishable** documentation
using filename suffixes.

### Development files

Files containing `_dev` in their name are considered **work in progress** and are **not committed**:
- `*_dev.xlsx`
- `*_dev.html`

These files are ignored via `.gitignore` and are used for:
- drafting content
- experimenting
- private or temporary documentation

### Publishable files

When documentation is ready to be shared:
- the `_dev` suffix is removed
- the file is committed intentionally

Typically:
- **Excel workbooks (`.xlsx`)** are committed as the source of truth
- **HTML output** may be committed for demo/showcase purposes, but can also be regenerated locally

### Rationale

This approach:
- prevents accidental publication of unfinished content
- keeps the repository clean and intentional
- allows others to generate HTML output locally from the Excel sources

> Rule of thumb:  
> **If it has `_dev` in the name, it stays local.  
> Removing `_dev` is a conscious publishing decision.**

## Status

Prototype (v0.6.0).

Current features:
- Excel → HTML generation
- Structured content via Chapter / Section
- Syntax highlighting via Prism.js
- Line numbers and copy-to-clipboard for code blocks
- Automatic navigation / table of contents
- Collapsible sections
- Light / Dark UI toggle (system default + persisted)
- Workbook selection via build script
- Multi-workbook output
- Shared images
- Optional portable ZIP packages
- Minimal dependencies (PowerShell + ImportExcel)
- Git workflow documentation (example workbook)
- Content-focused documentation (workflows over command reference)
- Go-to-top navigation for long documents

## License

Internal / educational use