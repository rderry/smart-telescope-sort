#!/usr/bin/env python3
"""Build the Smart Telescope Sort user manual PDF (bundled with the app)."""

from __future__ import annotations

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Resources" / "Smart-Telescope-Sort-User-Manual.pdf"

NAVY = colors.Color(0.05, 0.09, 0.18)
INK = colors.Color(0.12, 0.16, 0.24)
MUTED = colors.Color(0.35, 0.40, 0.48)
ACCENT = colors.Color(0.20, 0.38, 0.72)
CODE_BG = colors.Color(0.94, 0.96, 0.99)


def styles():
    base = getSampleStyleSheet()
    return {
        "cover_title": ParagraphStyle(
            "cover_title", parent=base["Title"], fontName="Helvetica-Bold",
            fontSize=24, leading=28, textColor=NAVY, alignment=TA_CENTER, spaceAfter=10,
        ),
        "cover_sub": ParagraphStyle(
            "cover_sub", parent=base["Normal"], fontName="Helvetica",
            fontSize=12, leading=16, textColor=MUTED, alignment=TA_CENTER, spaceAfter=8,
        ),
        "purpose": ParagraphStyle(
            "purpose", parent=base["Normal"], fontName="Helvetica-Oblique",
            fontSize=11, leading=16, textColor=INK, alignment=TA_CENTER,
            spaceBefore=14, spaceAfter=18,
        ),
        "h1": ParagraphStyle(
            "h1", parent=base["Heading1"], fontName="Helvetica-Bold",
            fontSize=15, leading=19, textColor=NAVY, spaceBefore=14, spaceAfter=8,
        ),
        "h2": ParagraphStyle(
            "h2", parent=base["Heading2"], fontName="Helvetica-Bold",
            fontSize=12, leading=15, textColor=ACCENT, spaceBefore=11, spaceAfter=6,
        ),
        "body": ParagraphStyle(
            "body", parent=base["Normal"], fontName="Helvetica",
            fontSize=10, leading=14, textColor=INK, alignment=TA_JUSTIFY, spaceAfter=8,
        ),
        "bullet": ParagraphStyle(
            "bullet", parent=base["Normal"], fontName="Helvetica",
            fontSize=10, leading=13, textColor=INK, leftIndent=4,
        ),
        "code": ParagraphStyle(
            "code", parent=base["Code"], fontName="Courier",
            fontSize=8.2, leading=11, textColor=INK, backColor=CODE_BG,
            leftIndent=6, rightIndent=6, spaceBefore=4, spaceAfter=10,
        ),
        "caption": ParagraphStyle(
            "caption", parent=base["Normal"], fontName="Helvetica-Oblique",
            fontSize=8.5, leading=11, textColor=MUTED, spaceAfter=10,
        ),
        "footer": ParagraphStyle(
            "footer", parent=base["Normal"], fontName="Helvetica",
            fontSize=8, textColor=MUTED, alignment=TA_CENTER,
        ),
    }


def bullets(items, style):
    return ListFlowable(
        [ListItem(Paragraph(i, style), leftIndent=12, bulletColor=ACCENT) for i in items],
        bulletType="bullet", start="•", leftIndent=18, spaceBefore=2, spaceAfter=8,
    )


def code_block(text, style):
    return Preformatted(text.rstrip() + "\n", style, maxLineLength=96)


def build():
    s = styles()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUT), pagesize=letter,
        leftMargin=0.75 * inch, rightMargin=0.75 * inch,
        topMargin=0.7 * inch, bottomMargin=0.7 * inch,
        title="Smart Telescope Sort User Manual",
        author="BigSkyAstro.com",
    )

    def add_page_number(canvas, _doc):
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.setFillColor(MUTED)
        canvas.drawCentredString(
            letter[0] / 2, 0.4 * inch,
            f"Smart Telescope Sort  ·  © 2026 BigSkyAstro.com  ·  {canvas.getPageNumber()}",
        )
        # Footer link
        canvas.setFillColor(colors.blue)
        canvas.linkURL("https://BigSkyAstro.com", (letter[0] / 2 - 80, 0.32 * inch, letter[0] / 2 + 80, 0.52 * inch))
        canvas.restoreState()

    story = []

    # Cover
    story.append(Spacer(1, 1.0 * inch))
    story.append(Paragraph("Smart Telescope Sort", s["cover_title"]))
    story.append(Paragraph("User Manual", s["cover_sub"]))
    story.append(Paragraph("macOS", s["cover_sub"]))
    story.append(
        Paragraph(
            '© 2026 <link href="https://BigSkyAstro.com" color="blue"><u>BigSkyAstro.com</u></link>',
            s["cover_sub"],
        )
    )
    story.append(
        Paragraph(
            "Organize TIFF and FITS captures from several smart-telescope brands into one "
            "year / object library. This app does not connect to the telescope — you copy "
            "sessions onto disk first, choose the matching telescope type, then Sort.",
            s["purpose"],
        )
    )
    story.append(
        Paragraph(
            "Separate from the Vaonis-only <b>Vespera Sort program</b>. Demo trees live next "
            "to this project under <font face='Courier'>Demo Captures/</font>.",
            s["body"],
        )
    )
    story.append(PageBreak())

    # 1 Assumptions
    story.append(Paragraph("1. Assumptions (read this first)", s["h1"]))
    story.append(
        Paragraph(
            "These assumptions are built into every telescope profile. If your workflow "
            "breaks them, Sort will mis-label objects or find nothing.",
            s["body"],
        )
    )
    story.append(bullets([
        "<b>You already moved files off the scope</b> (USB, FTP, or Wi‑Fi). Sort never talks "
        "to Vaonis, Seestar, DWARF, or Origin hardware.",
        "<b>Source Captures is one brand at a time.</b> Pick the telescope type in the "
        "sidebar to match the folder you point at. Do not mix Seestar albums and Vaonis "
        "dated sessions in the same Source Captures root for one preview.",
        "<b>Only TIFF / TIF / FIT / FITS are sorted.</b> JPG previews (Photos, phone album) "
        "are ignored. For processing keep TIFF/FITS; JPG is for viewing/sharing only.",
        "<b>Apple Photos is not a source.</b> Export to Files / a Captures folder if images "
        "only live in Photos.",
        "<b>Destination is always the same layout for every brand:</b> "
        "<font face='Courier'>Targets {year}/{DSO}/</font> under your Source Captures folder.",
        "<b>Year</b> comes from dated folder names when present; otherwise from the newest "
        "image file’s modification date.",
        "<b>DSO name</b> is decoded from observation / album / object folder names "
        "(normalized to uppercase, spaces → hyphens).",
        "<b>Replace only when newer.</b> If Targets already has the same filename, Sort "
        "keeps the newer copy and clears the older source duplicate.",
        "<b>Emptied parent capture folders are deleted</b> after Sort when no TIFF/FITS remain "
        "(sidecars go with them). <font face='Courier'>Targets …</font> folders are never "
        "scanned as sources and are never deleted by cleanup.",
        "<b>Optional backup</b> copies whole capture folders before any move.",
    ], s["bullet"]))

    story.append(Paragraph("1.1 What Sort does not do", s["h2"]))
    story.append(bullets([
        "It does not run stacking, stretching, or post-processing.",
        "It does not implement Unistellar (not in this build).",
        "It does not invent missing object names — if a dump folder has no usable name, "
        "the DSO label may be the parent folder name.",
    ], s["bullet"]))

    # 2 Destination
    story.append(Paragraph("2. Where sorted files go (all telescopes)", s["h1"]))
    story.append(
        Paragraph(
            "After Sort, every brand uses the same library shape so multi-night and "
            "multi-brand collections stay easy to browse:",
            s["body"],
        )
    )
    story.append(code_block(
        "{Source Captures}/Targets {year}/{DSO}/\n"
        "example:  …/Captures/Targets 2026/M31/\n"
        "example:  …/Demo Captures/Seestar/Targets 2026/M42/",
        s["code"],
    ))
    story.append(
        Paragraph(
            "Parent USB / FTP / dated session folders are emptied as files move. When a "
            "parent no longer holds TIFF/FITS, Sort removes that parent at the Captures root.",
            s["body"],
        )
    )

    # 3 Telescope picker
    story.append(Paragraph("3. Choose telescope type first", s["h1"]))
    story.append(
        Paragraph(
            "The sidebar <b>Telescope type</b> menu selects the scanner. The app remembers "
            "your last choice. Then set <b>Source Captures</b> (…) to the folder that holds "
            "<i>that</i> brand’s sessions — for demos, the brand subfolder under "
            "<font face='Courier'>Demo Captures/</font>, not the parent.",
            s["body"],
        )
    )
    story.append(code_block(
        "/Volumes/Large Drive/Smart Telescope Sort program/Demo Captures/\n"
        "  Vaonis/     ← telescope type: Vaonis\n"
        "  Seestar/    ← telescope type: Seestar\n"
        "  DWARF/      ← telescope type: DWARFLAB\n"
        "  Origin/     ← telescope type: Origin\n"
        "  README.txt",
        s["code"],
    ))
    story.append(
        Paragraph(
            "<b>Review file plan</b> opens a sheet listing every planned move / replace / "
            "keep (nothing moves yet). <b>Sort eligible files</b> offers backup, then moves.",
            s["body"],
        )
    )

    # 4 Per brand
    story.append(Paragraph("4. How each telescope gets files onto the Mac", s["h1"]))
    story.append(
        Paragraph(
            "Offload is done outside this app. Below: how vendors typically expose files, "
            "what Sort expects after you copy them into Captures, and demo coverage.",
            s["body"],
        )
    )

    story.append(Paragraph("4.1 Vaonis (Vespera / Stellina)", s["h2"]))
    story.append(bullets([
        "<b>Off the scope:</b> FTP the Singularity <b>User/</b> dated folders (primary). "
        "Newer Vespera 3 / Pro 2 also support USB-C transfer. Multi-night: stop each night "
        "so the project saves; FTP each night’s dated folder.",
        "<b>On disk (Captures):</b> keep dated names unchanged, e.g. "
        "<font face='Courier'>2026-09-21_11-43-55_observation_M31</font> or "
        "<font face='Courier'>…_plan_My_plan</font> with nested "
        "<font face='Courier'>01-observation-…</font> and <font face='Courier'>01-images-…</font>.",
        "<b>Demo:</b> <font face='Courier'>Demo Captures/Vaonis/</font> — four sessions "
        "(M31×2, NGC7023, plan Demo_Night).",
    ], s["bullet"]))
    story.append(code_block(
        "User/   (on telescope)\n"
        "  2026-09-10_22-15-03_observation_M31/\n"
        "    01-images-initial/\n"
        "      img-0001.tiff\n"
        "      img-0002.fits\n"
        "→ copy whole folder into Captures → Sort → Targets 2026/M31/",
        s["code"],
    ))

    story.append(Paragraph("4.2 ZWO Seestar (S30 / S30 Pro / S50)", s["h2"]))
    story.append(bullets([
        "<b>Off the scope:</b> USB cable (drive often named Seestar → <b>MyWorks</b> / object "
        "folders), Wi‑Fi / Station Mode file share, or app export of <b>FIT</b>. Not FTP-first. "
        "JPG often lands in the phone album — that is not Sort’s source.",
        "<b>On disk (Captures):</b> object albums with <font face='Courier'>.fit / .fits</font> "
        "inside (e.g. <font face='Courier'>M31/</font>, or a USB dump containing several albums).",
        "<b>Demo:</b> <font face='Courier'>Demo Captures/Seestar/</font> — USB dump, Wi‑Fi dump, "
        "root M45 album, S50 session.",
    ], s["bullet"]))
    story.append(code_block(
        "Seestar (USB) / MyWorks/\n"
        "  M31/\n"
        "    ….fit\n"
        "  NGC253/\n"
        "    ….fits\n"
        "→ copy albums (or the dump) into Captures → Sort → Targets {year}/M31/",
        s["code"],
    ))

    story.append(Paragraph("4.3 DWARFLAB (DWARF 3 / II / mini)", s["h2"]))
    story.append(bullets([
        "<b>Off the scope:</b> USB mass storage (appears as a disk) and/or FTP "
        "(often <font face='Courier'>ftp://192.168.88.1</font> on the DWARF Wi‑Fi). "
        "Session folders hold FITS/TIFF stacks and subs; JPG is for phone viewing.",
        "<b>On disk (Captures):</b> keep each session folder intact. Object may be a nested "
        "folder (e.g. <font face='Courier'>…/M33/</font>) under a dated session.",
        "<b>Demo:</b> <font face='Courier'>Demo Captures/DWARF/</font> — four sessions "
        "(DWARF 3, FTP-style, II, mini).",
    ], s["bullet"]))
    story.append(code_block(
        "DWARF USB / Astronomy / <session>/\n"
        "  M33/\n"
        "    stacked.fits\n"
        "    stacked.tiff\n"
        "    sub_0001.fits\n"
        "→ copy session into Captures → Sort → Targets {year}/M33/",
        s["code"],
    ))

    story.append(Paragraph("4.4 Celestron Origin Mark II", s["h2"]))
    story.append(bullets([
        "<b>Off the scope:</b> enable <b>Save Raw Images</b>, then copy via USB stick "
        "(FAT32/exFAT) from the app File Manager, or FTP to a computer. Stacked JPG to the "
        "phone gallery is not the Sort path.",
        "<b>On disk (Captures):</b> folders named object + date, e.g. "
        "<font face='Courier'>M31_2026-09-05/</font> with <font face='Courier'>.fits</font> "
        "(lights; sometimes flats/darks). A parent “USB dump” with several object+date "
        "folders is also supported.",
        "<b>Demo:</b> <font face='Courier'>Demo Captures/Origin/</font> — three object+date "
        "folders plus one nested USB dump.",
    ], s["bullet"]))
    story.append(code_block(
        "M31_2026-09-05/\n"
        "  raw_0001.fits   (or Light01.fits on real Origin)\n"
        "  raw_0002.fits\n"
        "→ copy into Captures → Sort → Targets 2026/M31/",
        s["code"],
    ))

    # 5 Workflow
    story.append(Paragraph("5. Recommended workflow", s["h1"]))
    story.append(bullets([
        "Copy sessions off the telescope into a Captures-style folder (or use Demo Captures).",
        "Launch <b>Smart Telescope Sort</b>.",
        "Set <b>Telescope type</b> to match those files.",
        "Set <b>Source Captures</b> (…) to that brand’s folder.",
        "Refresh preview. Create <font face='Courier'>Targets {year}</font> if offered.",
        "Use <b>Review file plan</b> to inspect every From → To action.",
        "Press <b>Sort eligible files</b> → optional backup → Sort now.",
        "Browse <font face='Courier'>Targets {year}/{DSO}</font> for stacking / archive.",
    ], s["bullet"]))

    # 6 Demo note
    story.append(Paragraph("6. Demo Captures", s["h1"]))
    story.append(
        Paragraph(
            "Under the project folder, <font face='Courier'>Demo Captures/</font> holds "
            "placeholder TIFF/FITS trees that mimic a post-transfer layout for each brand. "
            "They are not real images and not screenshots of vendor Finder windows — they "
            "exist so the preview and Sort path behave like a user’s machine after USB/FTP copy.",
            s["body"],
        )
    )
    story.append(code_block(
        "/Volumes/Large Drive/Smart Telescope Sort program/Demo Captures/",
        s["code"],
    ))

    # 7 Safety
    story.append(Paragraph("7. Safety rules", s["h1"]))
    story.append(bullets([
        "Nothing moves until you confirm Sort (after the backup offer).",
        "Replace destination files only when the source is newer.",
        "Never scan <font face='Courier'>Targets {year}</font> as a capture source.",
        "Never delete the Captures root or any Targets year folder during cleanup.",
        "Backup copies whole capture trees; it does not modify Targets.",
    ], s["bullet"]))

    story.append(Spacer(1, 14))
    story.append(
        Paragraph(
            "End of manual — Help → Smart Telescope Sort User Manual (⇧⌘/) opens this PDF.",
            s["caption"],
        )
    )

    doc.build(story, onFirstPage=add_page_number, onLaterPages=add_page_number)
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    build()
