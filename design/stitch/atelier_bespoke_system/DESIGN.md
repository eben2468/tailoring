---
name: Atelier Bespoke System
colors:
  surface: '#f9f9ff'
  surface-dim: '#cfdaf2'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f0f3ff'
  surface-container: '#e7eeff'
  surface-container-high: '#dee8ff'
  surface-container-highest: '#d8e3fb'
  on-surface: '#111c2d'
  on-surface-variant: '#45474c'
  inverse-surface: '#263143'
  inverse-on-surface: '#ecf1ff'
  outline: '#75777d'
  outline-variant: '#c5c6cd'
  surface-tint: '#535f75'
  primary: '#000000'
  on-primary: '#ffffff'
  primary-container: '#101c2f'
  on-primary-container: '#78849c'
  inverse-primary: '#bbc7e0'
  secondary: '#0051d5'
  on-secondary: '#ffffff'
  secondary-container: '#316bf3'
  on-secondary-container: '#fefcff'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#002113'
  on-tertiary-container: '#009668'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d7e3fd'
  primary-fixed-dim: '#bbc7e0'
  on-primary-fixed: '#101c2f'
  on-primary-fixed-variant: '#3c475c'
  secondary-fixed: '#dbe1ff'
  secondary-fixed-dim: '#b4c5ff'
  on-secondary-fixed: '#00174b'
  on-secondary-fixed-variant: '#003ea8'
  tertiary-fixed: '#6ffbbe'
  tertiary-fixed-dim: '#4edea3'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005236'
  background: '#f9f9ff'
  on-background: '#111c2d'
  surface-variant: '#d8e3fb'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 26px
    fontWeight: '700'
    lineHeight: 34px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.01em
  title-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 15px
    fontWeight: '600'
    lineHeight: 20px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 22px
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  body-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.04em
  metric-num:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 24px
    letterSpacing: -0.01em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 0.75rem
  gutter-tablet: 1rem
  margin: 1rem
  margin-tablet: 1.5rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.5rem
---

## Brand & Style

This design system embodies the meticulous precision, discretion, and quiet luxury of bespoke sartorial craftsmanship, translated into an ultra-efficient mobile operating environment. Built specifically for master tailors, cutters, and luxury studio managers, the interface bridges artisanal tradition with razor-sharp SaaS clarity.

The visual style is **Contemporary Corporate Luxury**: confident, structured, uncluttered, and precise. It eschews generic startup softness in favor of tailored restraint: crisp hairline divider strokes that evoke fine fabric cuts, calibrated negative space, and deep midnight foundational tones that anchor high-value client workflows. The emotional resonance is calm mastery, absolute control over production schedules, and respect for physical craftsmanship.

## Colors

The palette establishes an immediate sense of discipline, prestige, and practical readability under varied studio lighting conditions.

### Architectural Foundations
- **Primary Canvas & Contrast**: Midnight Deep Navy (`#0F1B2E`) serves as the root anchoring tone, applied across high-priority navigation structures, top utility headers, active state triggers, and primary actions. Secondary elevation tone `#16243B` delivers subtle separation on darker surfaces.
- **Canvas Neutrals**: The viewport relies on Crisp White (`#FFFFFF`) for elevated cards, backed by Soft Slate Canvas (`#F4F6F9`) for screen backdrops. Subtle outlines and hairline separators utilize Soft Slate Gray (`#E2E8F0`).
- **Typography Neutrals**: Dark Slate Charcoal (`#1E293B`) commands primary headlines, client labels, and measurement inputs, while muted operational metadata is handled by Slate Muted (`#64748B`).

### Functional Accents & Tailoring Workflow States
- **In-Progress / Fitting Active**: Tailor Blue (`#2563EB`) paired with surface tone Soft Blue (`#EFF6FF`).
- **Completed / Basted / Approved**: Atelier Green (`#10B981`) paired with surface tone Soft Mint (`#ECFDF5`).
- **Approaching Deadline / Needs Fitting**: Amber Warning (`#F59E0B`) with surface tone Soft Sand (`#FFFBEB`).
- **Critical / Alteration Overdue**: Crimson Urgent (`#EF4444`) with surface tone Soft Rose (`#FEF2F2`).
- **Pending Cloth / Inactive Pattern**: Muted Slate (`#64748B`) with surface tone Chalk Gray (`#F1F5F9`).

Status badges must always combine the specific saturated border/text value with its corresponding soft background container, avoiding harsh eye fatigue during prolonged mobile scheduling sessions.

## Typography

The typography uses **Plus Jakarta Sans** uniformly across display, body, and micro-labeling layers to present a sharp, modern, geometric presence with humanist approachability. 

### Tabular Numerical Treatment
Given the density of measurements (chest circumference, sleeve length, shoulder slope, collar pitch) and critical delivery deadlines, all numerical representations must activate OpenType tabular figures (`font-variant-numeric: tabular-nums`). This guarantees perfect vertical column alignment in garment measurement ledgers, ledger tables, cost breakdowns, and lead-time schedules.

### Structural Scale
- **Headings**: Tightly tracked (-0.01em to -0.02em) with deliberate weight distribution to command immediate authority on handheld screens.
- **Micro Labels & Stage Tags**: Rendered in uppercase or deliberate medium-semi-bold weights with slight letter tracking (+0.02em to +0.04em) to maintain crisp character separation at 11–12px on high-density mobile displays.

## Layout & Spacing

The layout is engineered from a mobile-first perspective with a strict 4px/8px incremental rhythm, adapting cleanly to tablets used during client consultations.

### Form Factors & Adaptation
- **Mobile (Default, 360px – 599px)**: Single-column flow structured around a 4-column fluid layout with an outer canvas boundary of `margin: 1rem` (16px) and interior element column gutter of `gutter: 0.75rem` (12px). Quick-access thumb zones place primary action buttons and floating progress indicators within the lower screen quadrant.
- **Tablet / Countertop POS (600px – 1024px)**: Transitions to an 8-column layout with `margin-tablet: 1.5rem` (24px). The layout introduces a master-detail split screen: left rail for active production jobs, right canvas for measurement schematics, cloth swatches, and client interaction records.

### Content Density
To prevent visual fatigue while keeping maximum operational data within view:
- Form fields and measurement cards use compact vertical internal padding (`space-md`).
- Macro-sections (Client profile, Suit specifications, Fitting logs) divide cleanly using `space-xl` margins.

## Elevation & Depth

Visual hierarchy leverages a hybrid model of **ambient micro-shadows** combined with **subtle hairline borders** (1px solid `#E2E8F0`), creating a refined physical tactile presence akin to crisp heavy-stock card stationery.

### Elevation Hierarchy
- **Level 0 (Base Canvas)**: Soft Slate (`#F4F6F9`). Flat with zero elevation.
- **Level 1 (Content Cards & Grid Modules)**: Crisp White (`#FFFFFF`) framed by a 1px solid `#E2E8F0` stroke and a resting micro-shadow (`box-shadow: 0 1px 3px rgba(15, 27, 46, 0.04), 0 1px 2px rgba(15, 27, 46, 0.02)`).
- **Level 2 (Active Touch & Focused Job Tiles)**: Crisp White surface with increased separation (`box-shadow: 0 4px 12px rgba(15, 27, 46, 0.08), 0 2px 4px rgba(15, 27, 46, 0.04)`), applied during long-press drag-and-drop workflow status updates.
- **Level 3 (Modal Sheets, Fitting Drawers & Bottom Bar)**: Solid White (`#FFFFFF`) with a top border hairline (`#E2E8F0`) and diffused elevation (`box-shadow: 0 -4px 20px rgba(15, 27, 46, 0.08)`).

## Shapes

The design system employs **Roundedness 2** (base radius of 0.5rem / 8px for smaller interactive inputs, scaling up to 0.875rem–1rem / 14–16px for primary modular cards).

### Radius Calibration
- **Primary Content Cards & Job Cards**: Explicitly capped between 14px and 16px (`rounded-lg`), mirroring high-end handheld stationery folders.
- **Buttons & Text Inputs**: Standardized at 8px to 10px (`rounded`), balancing modern geometric structure with easy finger targeting.
- **Status Pills, Stage Badges & Circular Indicators**: Full pill radius (`rounded-full` / 9999px) to maintain immediate semantic contrast against rectangular cards.
- **Circular Progress Trackers**: Pure geometric circles with clean 2.5px to 3.5px SVG stroke caps for garment completion percentages.

## Components

### Buttons
- **Primary Button**: Deep Navy (`#0F1B2E`) background, crisp white typography, 10px border radius, 48px standard touch height on mobile. Subtle active state transitions to `#16243B`.
- **Secondary Button**: Clean white surface with a 1px border of `#E2E8F0`, dark slate text (`#1E293B`), active state `#F4F6F9`.
- **Destructive/Urgent Action**: Soft rose background (`#FEF2F2`) with red coral text (`#EF4444`) and subtle border stroke (`#FCA5A5`).

### Stage Step Progress Bars & Circular Trackers
- **Stage Step Bars**: Segmented horizontal rails representing standard tailoring progressions (e.g., *1. Pattern Cut → 2. First Fitting / Baste → 3. Forward Fitting → 4. Hand Finishing → 5. Ready for Collection*). Uncompleted stages display Slate `#E2E8F0`; active stage fills with Tailor Blue (`#2563EB`) with a pulse pip; completed stages lock in Atelier Green (`#10B981`).
- **Circular Trackers**: 40px–56px SVG rings indicating total order completion percentage, positioned within high-level client cards.

### Status Pills & Chips
- Compact pills utilizing 4px vertical by 10px horizontal padding with `label-sm` typography. 
- Strict paired mapping: Saturated indicator dot (6px) + colored text label set against its paired soft background container (e.g., `#ECFDF5` container with `#10B981` text for *Ready for Fitting*).

### Garment Measurement Inputs
- Specialized dual-column cells optimized for numeric keypad entry. Includes fixed unit indicator adornments (`in` or `cm`) in `label-sm` font. Border focuses to 1.5px `#2563EB` on tap with automatic step-to-next-field navigation.

### Bottom Bar Navigation
- Fixed 64px mobile dock housing 5 primary destinations: **Dashboard**, **Jobs**, **Calendar**, **Customers**, **More**.
- Crisp White surface backed by subtle frosted blur and top 1px hairline border.
- Active item uses Deep Navy fill icon with an indicator dot; inactive items utilize `#64748B`.

### Bespoke Tailoring Domain Icons
- Tailored SVG glyph suite rendered with a uniform 1.75px stroke: shears/scissors, tape measure, floating suit silhouette, needle & thread, and draped garment bag.