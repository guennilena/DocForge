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
│ └─ build-docs.ps1 # Documentation generator
├─ docs/
│ ├─ source/
│ │ └─ docs.xlsx # Documentation source (Excel)
│ └─ out/
│ └─ index.html # Generated HTML (build output)
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

## Status

Early prototype (v0.1.0).

The current version focuses on:
- Excel → HTML generation
- clean structure
- minimal dependencies

## License

Internal / educational use