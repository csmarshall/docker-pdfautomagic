#!/usr/bin/env python3
"""
PDF Auto-Splitter using Vision AI

Analyzes a multi-page PDF (e.g., a stack of scanned mail) and:
1. Removes blank pages
2. Detects document boundaries using vision AI
3. Splits into separate PDFs
"""

import argparse
import base64
import io
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Tuple

import ollama
from pdf2image import convert_from_path
from PIL import Image
from pypdf import PdfReader, PdfWriter

# Ollama server URL (runs as process in same container by default)
# Can override via OLLAMA_HOST for remote Ollama setups
OLLAMA_HOST = os.environ.get('OLLAMA_HOST', 'http://localhost:11434')


def log(message: str = "", end: str = "\n") -> None:
    """Print timestamped progress messages to stderr so they appear in container logs."""
    from datetime import datetime, timezone
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    # Only add timestamp prefix for non-empty, non-continuation lines
    if message and not message.startswith("  "):
        print(f"[{timestamp}] split_pdf.py - {message}", end=end, file=sys.stderr, flush=True)
    else:
        print(message, end=end, file=sys.stderr, flush=True)


def detect_gpu() -> Tuple[bool, str]:
    """
    Detect if a GPU is available for Ollama.
    Checks in priority order: NVIDIA (CUDA) → AMD (ROCm) → Apple Silicon (Metal)
    Intel GPUs are detected but not supported by Ollama.

    Returns (gpu_available, description).
    """
    detected_gpus = []

    # Priority 1: NVIDIA (CUDA) - best support
    if shutil.which('nvidia-smi'):
        try:
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=name', '--format=csv,noheader'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                gpu_name = result.stdout.strip().split('\n')[0]
                return True, f"NVIDIA (CUDA): {gpu_name}"
        except (subprocess.TimeoutExpired, Exception):
            pass

    # Priority 2: AMD (ROCm) - Linux only
    if shutil.which('rocm-smi'):
        try:
            result = subprocess.run(
                ['rocm-smi', '--showproductname'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                # Parse GPU name from rocm-smi output
                lines = result.stdout.strip().split('\n')
                for line in lines:
                    if 'GPU' in line or 'Card' in line:
                        return True, f"AMD (ROCm): {line.strip()}"
                return True, "AMD (ROCm): GPU detected"
        except (subprocess.TimeoutExpired, Exception):
            pass

    # Priority 3: Apple Silicon (Metal)
    if sys.platform == 'darwin':
        try:
            result = subprocess.run(
                ['sysctl', '-n', 'machdep.cpu.brand_string'],
                capture_output=True, text=True, timeout=5
            )
            if 'Apple' in result.stdout:
                chip = result.stdout.strip()
                return True, f"Apple Silicon (Metal): {chip}"
        except (subprocess.TimeoutExpired, Exception):
            pass

    # Check for Intel GPU (not supported, but give helpful message)
    intel_gpu = _detect_intel_gpu()
    if intel_gpu:
        return False, f"Intel GPU detected ({intel_gpu}) but NOT SUPPORTED by Ollama. Use NVIDIA, AMD, or Apple Silicon."

    return False, "No supported GPU detected (checked: NVIDIA/CUDA, AMD/ROCm, Apple/Metal)"


def _detect_intel_gpu() -> Optional[str]:
    """Check for Intel GPU (for informational purposes - not supported)."""
    # Linux: check lspci
    if shutil.which('lspci'):
        try:
            result = subprocess.run(
                ['lspci'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'Intel' in line and ('VGA' in line or 'Display' in line or 'Graphics' in line):
                        # Extract GPU name
                        if ':' in line:
                            return line.split(':')[-1].strip()
                        return "Intel Graphics"
        except (subprocess.TimeoutExpired, Exception):
            pass

    # Windows: check via wmic (if ever needed)
    if sys.platform == 'win32' and shutil.which('wmic'):
        try:
            result = subprocess.run(
                ['wmic', 'path', 'win32_videocontroller', 'get', 'name'],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0 and 'Intel' in result.stdout:
                for line in result.stdout.split('\n'):
                    if 'Intel' in line:
                        return line.strip()
        except (subprocess.TimeoutExpired, Exception):
            pass

    return None


class DetectionNotAvailableError(Exception):
    """Raised when detection is requested but not available."""
    pass


def check_ollama_reachable() -> Tuple[bool, str]:
    """Check if Ollama server is reachable."""
    import urllib.request
    import urllib.error

    try:
        url = f"{OLLAMA_HOST}/api/tags"
        req = urllib.request.Request(url, method='GET')
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                return True, f"Ollama server reachable at {OLLAMA_HOST}"
    except urllib.error.URLError as e:
        return False, f"Cannot reach Ollama at {OLLAMA_HOST}: {e.reason}"
    except Exception as e:
        return False, f"Cannot reach Ollama at {OLLAMA_HOST}: {e}"

    return False, f"Ollama server not responding at {OLLAMA_HOST}"


def check_detection_available(allow_cpu: bool = False) -> Tuple[bool, bool, str]:
    """
    Check if detection is available and determine execution mode.

    Args:
        allow_cpu: If True, allow CPU fallback when no GPU detected

    Returns:
        (available, using_gpu, message)
    """
    # If using remote Ollama (sidecar), check connectivity instead of local GPU
    if OLLAMA_HOST != 'http://localhost:11434':
        reachable, msg = check_ollama_reachable()
        if reachable:
            return True, True, f"Remote Ollama: {msg}"
        else:
            return False, False, f"ERROR: {msg}\nEnsure the Ollama sidecar container is running."

    # Local Ollama - check for GPU
    gpu_available, gpu_desc = detect_gpu()

    if gpu_available:
        return True, True, f"GPU detected: {gpu_desc}"

    # Check if Intel GPU was detected (not supported)
    intel_gpu = _detect_intel_gpu()
    if intel_gpu:
        if allow_cpu:
            return True, False, (
                f"WARNING: Intel GPU detected ({intel_gpu}) but not supported by Ollama.\n"
                "Using CPU fallback - this will be significantly slower.\n"
                "Track Intel GPU support: https://github.com/ollama/ollama/issues/781"
            )
        else:
            return False, False, (
                f"ERROR: Intel GPU detected ({intel_gpu}) but NOT SUPPORTED by Ollama.\n"
                "\n"
                "Ollama currently only supports: NVIDIA (CUDA), AMD (ROCm), Apple Silicon (Metal)\n"
                "\n"
                "Options:\n"
                "  1. Use a system with a supported GPU\n"
                "  2. Set --allow-cpu to enable slow CPU processing\n"
                "  3. Disable detection and use standard OCR only\n"
                "\n"
                "Track Intel GPU support at:\n"
                "  https://github.com/ollama/ollama/issues/781"
            )

    # No GPU at all
    if allow_cpu:
        return True, False, "WARNING: No GPU detected. Using CPU - this will be significantly slower."
    else:
        return False, False, (
            "ERROR: Splitting enabled but no GPU detected and CPU fallback not allowed.\n"
            "Options:\n"
            "  1. Use a system with NVIDIA, AMD, or Apple Silicon GPU\n"
            "  2. Set --allow-cpu to enable slow CPU processing\n"
            "  3. Disable detection and use standard OCR only"
        )


@dataclass
class PageAnalysis:
    """Analysis result for a single page."""
    page_number: int
    is_blank: bool
    is_first_page: bool
    confidence: float
    reasoning: str = ""


@dataclass
class DocumentInfo:
    """Classification info for a document."""
    doc_type: str = "unknown"
    sender: str = ""
    date: str = ""
    reference: str = ""
    confidence: float = 0.0
    suggested_filename: str = ""

    def to_dict(self) -> dict:
        return {
            "doc_type": self.doc_type,
            "sender": self.sender,
            "date": self.date,
            "reference": self.reference,
            "confidence": self.confidence,
            "suggested_filename": self.suggested_filename,
        }


@dataclass
class DetectionResult:
    """Results from detecting and splitting a PDF."""
    input_file: str
    pages_input: int = 0
    pages_blank_removed: int = 0
    pages_processed: int = 0
    documents_output: int = 0
    boundaries_detected: list = field(default_factory=list)
    confidence_scores: list = field(default_factory=list)
    processing_time_sec: float = 0.0
    model_calls: int = 0
    output_files: list = field(default_factory=list)
    classifications: list = field(default_factory=list)
    errors: list = field(default_factory=list)

    @property
    def avg_pages_per_document(self) -> float:
        if self.documents_output == 0:
            return 0.0
        return self.pages_processed / self.documents_output

    @property
    def low_confidence_pages(self) -> list:
        return [i for i, score in enumerate(self.confidence_scores) if score < 0.7]

    def to_dict(self) -> dict:
        return {
            "input_file": self.input_file,
            "pages_input": self.pages_input,
            "pages_blank_removed": self.pages_blank_removed,
            "pages_processed": self.pages_processed,
            "documents_output": self.documents_output,
            "boundaries_detected": self.boundaries_detected,
            "confidence_scores": self.confidence_scores,
            "avg_pages_per_document": round(self.avg_pages_per_document, 2),
            "low_confidence_pages": self.low_confidence_pages,
            "processing_time_sec": round(self.processing_time_sec, 2),
            "model_calls": self.model_calls,
            "output_files": self.output_files,
            "classifications": [c.to_dict() for c in self.classifications],
            "errors": self.errors,
        }


class PDFSplitter:
    """Splits multi-document PDFs using vision AI for boundary detection."""

    BLANK_THRESHOLD = 0.97  # Pages with >97% white pixels are blank
    MODEL_NAME = "qwen2.5vl:7b"

    FIRST_PAGE_PROMPT = """Analyze this scanned document page. Is this the FIRST page of a new document/letter, or is it a CONTINUATION page from a previous document?

FIRST PAGE indicators (strong signals for a NEW document):
- Letterhead or company logo at the top
- Date prominently displayed near the top
- Recipient address block ("Dear Customer", mailing address)
- Greeting/salutation ("Dear...", "To whom it may concern")
- Subject line or reference number introduction
- "Page 1" or "Page 1 of X"
- Account statement header with account holder info
- Invoice header with invoice number and date

CONTINUATION PAGE indicators (this page belongs with the PREVIOUS document):
- Page number > 1 (e.g., "Page 2", "2 of 3")
- No letterhead - just content continuing
- Tables/spreadsheets with transaction details or line items
- Text that appears to continue from a previous page
- "...continued" or similar
- Landscape orientation with tabular data (registers, detailed breakdowns)

NOTE: Orientation changes alone do NOT indicate a new document. A landscape spreadsheet page typically belongs with the preceding portrait cover page.

Respond with ONLY a JSON object:
{"is_first_page": true, "confidence": 0.95, "reasoning": "brief explanation"}"""

    CLASSIFY_PROMPT = """Analyze this document's first page and extract key information for filing purposes.

Extract the following:
1. doc_type: The type of document. Choose ONE from:
   - bill (utility bills, invoices requesting payment)
   - statement (bank/credit card/investment statements)
   - letter (personal or business correspondence)
   - notice (official notices, announcements, alerts)
   - medical (EOBs, medical records, healthcare correspondence)
   - tax (tax forms, tax-related documents)
   - legal (contracts, legal notices, court documents)
   - insurance (policy documents, claims, insurance correspondence)
   - receipt (purchase receipts, confirmations)
   - advertisement (marketing, promotions, junk mail)
   - other (if none of the above fit)

2. sender: The company or person who sent this document.
   - Use the official company name (e.g., "Comcast" not "Comcast Corporation")
   - For individuals, use "FirstName LastName"
   - If unclear, use empty string ""

3. date: The document date (not today's date).
   - Format: YYYY-MM-DD
   - Look for statement date, letter date, invoice date, etc.
   - If unclear, use empty string ""

4. reference: Any account number, invoice number, or reference ID.
   - Just the number/ID, no labels
   - If unclear, use empty string ""

Respond with ONLY a JSON object:
{"doc_type": "bill", "sender": "Comcast", "date": "2026-01-10", "reference": "8423-1234-5678", "confidence": 0.9}"""

    def __init__(self, model_name: Optional[str] = None, blank_threshold: Optional[float] = None):
        self.model_name = model_name or self.MODEL_NAME
        self.blank_threshold = blank_threshold or self.BLANK_THRESHOLD

    def is_page_blank(self, image: Image.Image) -> bool:
        """Check if a page is blank (mostly white)."""
        grayscale = image.convert('L')
        pixels = list(grayscale.tobytes())
        white_pixels = sum(1 for p in pixels if p > 240)
        white_ratio = white_pixels / len(pixels)
        return white_ratio > self.blank_threshold

    def image_to_base64(self, image: Image.Image, max_size: int = 1024) -> str:
        """Convert PIL Image to base64 string, resizing if needed."""
        # Resize to reduce token usage while preserving readability
        if max(image.size) > max_size:
            ratio = max_size / max(image.size)
            new_size = (int(image.size[0] * ratio), int(image.size[1] * ratio))
            image = image.resize(new_size, Image.Resampling.LANCZOS)

        buffer = io.BytesIO()
        image.save(buffer, format='PNG')
        return base64.b64encode(buffer.getvalue()).decode('utf-8')

    def analyze_page(self, image: Image.Image) -> PageAnalysis:
        """Use vision AI to determine if this is a first page."""
        try:
            response = ollama.chat(
                model=self.model_name,
                messages=[{
                    'role': 'user',
                    'content': self.FIRST_PAGE_PROMPT,
                    'images': [self.image_to_base64(image)]
                }]
            )

            # Parse JSON response
            content = response['message']['content']
            # Try to extract JSON from response
            try:
                # Handle case where model wraps JSON in markdown
                if '```json' in content:
                    content = content.split('```json')[1].split('```')[0]
                elif '```' in content:
                    content = content.split('```')[1].split('```')[0]

                result = json.loads(content.strip())
                return PageAnalysis(
                    page_number=-1,  # Set by caller
                    is_blank=False,
                    is_first_page=result.get('is_first_page', True),
                    confidence=float(result.get('confidence', 0.5)),
                    reasoning=result.get('reasoning', '')
                )
            except json.JSONDecodeError:
                # If we can't parse JSON, try to infer from text
                is_first = 'first' in content.lower() and 'not' not in content.lower()[:50]
                return PageAnalysis(
                    page_number=-1,
                    is_blank=False,
                    is_first_page=is_first,
                    confidence=0.5,
                    reasoning=f"Could not parse JSON, inferred from: {content[:100]}"
                )

        except Exception as e:
            return PageAnalysis(
                page_number=-1,
                is_blank=False,
                is_first_page=True,  # Default to treating as new document
                confidence=0.0,
                reasoning=f"Error: {str(e)}"
            )

    def classify_document(self, image: Image.Image) -> DocumentInfo:
        """Use vision AI to classify a document and extract metadata."""
        try:
            response = ollama.chat(
                model=self.model_name,
                messages=[{
                    'role': 'user',
                    'content': self.CLASSIFY_PROMPT,
                    'images': [self.image_to_base64(image)]
                }]
            )

            content = response['message']['content']
            try:
                if '```json' in content:
                    content = content.split('```json')[1].split('```')[0]
                elif '```' in content:
                    content = content.split('```')[1].split('```')[0]

                result = json.loads(content.strip())

                doc_info = DocumentInfo(
                    doc_type=result.get('doc_type', 'unknown'),
                    sender=result.get('sender', ''),
                    date=result.get('date', ''),
                    reference=result.get('reference', ''),
                    confidence=float(result.get('confidence', 0.5)),
                )

                # Generate suggested filename
                doc_info.suggested_filename = self._generate_filename(doc_info)
                return doc_info

            except json.JSONDecodeError:
                return DocumentInfo(
                    doc_type='unknown',
                    confidence=0.0,
                    suggested_filename='unknown_document'
                )

        except Exception as e:
            return DocumentInfo(
                doc_type='unknown',
                confidence=0.0,
                suggested_filename='unknown_document'
            )

    def _title_case(self, text: str) -> str:
        """
        Convert text to title case with lowercase articles/prepositions.

        Examples:
            "VILLAGE OF SKOKIE" -> "Village of Skokie"
            "BANK OF AMERICA" -> "Bank of America"
            "THE HOME DEPOT" -> "The Home Depot"
        """
        # Words that should remain lowercase (unless first word)
        minor_words = {'a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'in',
                       'nor', 'of', 'on', 'or', 'so', 'the', 'to', 'up', 'yet'}
        words = text.lower().split()
        result = []
        for i, word in enumerate(words):
            # First word is always capitalized
            if i == 0 or word not in minor_words:
                result.append(word.capitalize())
            else:
                result.append(word)
        return ' '.join(result)

    def _generate_filename(self, doc_info: DocumentInfo) -> str:
        """Generate a descriptive filename from document info."""
        import re

        parts = []

        # Date first (for chronological sorting)
        if doc_info.date:
            parts.append(doc_info.date)

        # Sender name (sanitized and title-cased)
        if doc_info.sender:
            # Normalize case: "VILLAGE OF SKOKIE" -> "Village of Skokie"
            sender = self._title_case(doc_info.sender)
            # Remove special characters, replace spaces with underscores
            sender = re.sub(r'[^\w\s-]', '', sender)
            sender = re.sub(r'\s+', '_', sender.strip())
            if sender:
                parts.append(sender)

        # Document type
        if doc_info.doc_type and doc_info.doc_type != 'unknown':
            parts.append(doc_info.doc_type.capitalize())

        # Reference number for disambiguation (sanitized)
        if doc_info.reference:
            ref = re.sub(r'[^\w-]', '', doc_info.reference)
            if ref:
                parts.append(ref)

        # If we have nothing useful, fall back
        if not parts:
            return 'document'

        return '_'.join(parts)

    def split_pdf(self, input_path: Path, output_dir: Path,
                  base_name: Optional[str] = None,
                  classify: bool = False) -> DetectionResult:
        """
        Split a PDF into multiple documents based on content analysis.

        Args:
            input_path: Path to input PDF
            output_dir: Directory for output PDFs
            base_name: Base name for output files (default: input filename)
            classify: If True, classify documents and use smart naming

        Returns:
            DetectionResult with metrics and output file paths
        """
        start_time = time.time()
        result = DetectionResult(input_file=str(input_path))

        if base_name is None:
            base_name = input_path.stem

        output_dir.mkdir(parents=True, exist_ok=True)

        # Load PDF
        try:
            pdf_reader = PdfReader(input_path)
            result.pages_input = len(pdf_reader.pages)
        except Exception as e:
            result.errors.append(f"Failed to read PDF: {e}")
            return result

        # Convert to images for analysis
        log(f"Converting {result.pages_input} pages to images...")
        try:
            images = convert_from_path(input_path, dpi=150)
        except Exception as e:
            result.errors.append(f"Failed to convert PDF to images: {e}")
            return result

        # Analyze each page
        page_analyses = []
        log("Analyzing pages...")

        for i, image in enumerate(images):
            page_num = i + 1

            # Check for blank page first
            if self.is_page_blank(image):
                log(f"Page {page_num}/{result.pages_input}: BLANK (removed)")
                result.pages_blank_removed += 1
                page_analyses.append(PageAnalysis(
                    page_number=page_num,
                    is_blank=True,
                    is_first_page=False,
                    confidence=1.0,
                    reasoning="Blank page detected"
                ))
                continue

            # Analyze with vision AI
            result.model_calls += 1
            analysis = self.analyze_page(image)
            analysis.page_number = page_num
            page_analyses.append(analysis)
            result.confidence_scores.append(analysis.confidence)

            status = "FIRST PAGE" if analysis.is_first_page else "continuation"
            log(f"Page {page_num}/{result.pages_input}: {status} (confidence: {analysis.confidence:.2f})")

            if analysis.is_first_page:
                result.boundaries_detected.append(page_num)

        result.pages_processed = result.pages_input - result.pages_blank_removed

        # Group pages into documents
        documents = []
        current_doc_pages = []

        first_non_blank = True
        for i, analysis in enumerate(page_analyses):
            if analysis.is_blank:
                continue

            # First non-blank page always starts a new document
            if first_non_blank:
                first_non_blank = False
            elif analysis.is_first_page and current_doc_pages:
                documents.append(current_doc_pages)
                current_doc_pages = []

            current_doc_pages.append(i)  # Original page index

        if current_doc_pages:
            documents.append(current_doc_pages)

        result.documents_output = len(documents)

        # Classify documents if requested
        if classify:
            log(f"Classifying {result.documents_output} documents...")
            for doc_idx, page_indices in enumerate(documents):
                first_page_idx = page_indices[0]
                result.model_calls += 1
                doc_info = self.classify_document(images[first_page_idx])
                result.classifications.append(doc_info)
                log(f"Document {doc_idx + 1}/{result.documents_output}: {doc_info.doc_type} from '{doc_info.sender}' ({doc_info.date})")

        # Write output PDFs
        log(f"Writing {result.documents_output} documents...")
        used_filenames = set()

        # Pre-populate with existing files in output directory
        for existing in output_dir.glob("*.pdf"):
            used_filenames.add(existing.stem)

        for doc_idx, page_indices in enumerate(documents):
            # Generate filename
            if classify and doc_idx < len(result.classifications):
                doc_info = result.classifications[doc_idx]
                filename_base = doc_info.suggested_filename
            else:
                filename_base = f"{base_name}_doc{doc_idx + 1:03d}"

            # Ensure unique filename (check both batch and existing files)
            filename = filename_base
            counter = 1
            while filename in used_filenames:
                filename = f"{filename_base}_{counter}"
                counter += 1
            used_filenames.add(filename)

            output_path = output_dir / f"{filename}.pdf"

            writer = PdfWriter()
            for page_idx in page_indices:
                writer.add_page(pdf_reader.pages[page_idx])

            with open(output_path, 'wb') as f:
                writer.write(f)

            result.output_files.append(str(output_path))
            log(f"Wrote {output_path.name} ({len(page_indices)} pages)")

        result.processing_time_sec = time.time() - start_time
        return result


def main():
    parser = argparse.ArgumentParser(
        description="Split a multi-document PDF into separate files"
    )
    parser.add_argument("input", type=Path, nargs='?', help="Input PDF file")
    parser.add_argument("-o", "--output-dir", type=Path, default=Path("./output"),
                        help="Output directory for split PDFs")
    parser.add_argument("-n", "--base-name", type=str, default=None,
                        help="Base name for output files")
    parser.add_argument("-m", "--model", type=str, default="qwen2.5vl:7b",
                        help="Ollama model to use for vision analysis")
    parser.add_argument("-b", "--blank-threshold", type=float, default=0.97,
                        help="White pixel ratio threshold for blank detection (0-1)")
    parser.add_argument("-c", "--classify", action="store_true",
                        help="Classify documents and use smart naming")
    parser.add_argument("--allow-cpu", action="store_true",
                        help="Allow CPU fallback if no GPU detected (slow)")
    parser.add_argument("--check-gpu", action="store_true",
                        help="Check GPU availability and exit")
    parser.add_argument("--json", action="store_true",
                        help="Output results as JSON")

    args = parser.parse_args()

    # GPU check mode
    if args.check_gpu:
        gpu_available, gpu_desc = detect_gpu()
        if gpu_available:
            log(f"GPU available: {gpu_desc}")
            sys.exit(0)
        else:
            log(f"No GPU: {gpu_desc}")
            sys.exit(1)

    # Check if detection is available
    available, using_gpu, message = check_detection_available(allow_cpu=args.allow_cpu)
    log(message)

    if not available:
        sys.exit(1)

    if not using_gpu:
        log("=" * 50)
        log("PROCEEDING WITH CPU - EXPECT SLOW PERFORMANCE")
        log("=" * 50)

    # Require input file for actual processing
    if not args.input:
        print("Error: Input PDF file required", file=sys.stderr)
        parser.print_usage()
        sys.exit(1)

    if not args.input.exists():
        print(f"Error: Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    splitter = PDFSplitter(model_name=args.model, blank_threshold=args.blank_threshold)
    result = splitter.split_pdf(args.input, args.output_dir, args.base_name, classify=args.classify)

    if args.json:
        # JSON goes to stdout for shell script to capture
        print(json.dumps(result.to_dict(), indent=2))
    else:
        # Human-readable output goes to stderr
        log("="*50)
        log("RESULTS")
        log("="*50)
        log(f"Input file:           {result.input_file}")
        log(f"Pages in:             {result.pages_input}")
        log(f"Blank pages removed:  {result.pages_blank_removed}")
        log(f"Pages processed:      {result.pages_processed}")
        log(f"Documents created:    {result.documents_output}")
        log(f"Avg pages/doc:        {result.avg_pages_per_document:.1f}")
        log(f"Processing time:      {result.processing_time_sec:.1f}s")
        log(f"Model calls:          {result.model_calls}")

        if result.boundaries_detected:
            log(f"Split at pages:       {result.boundaries_detected}")

        if result.low_confidence_pages:
            log(f"Low confidence pages: {result.low_confidence_pages}")

        if result.errors:
            log(f"Errors:               {result.errors}")

        if result.classifications:
            log("Classifications:")
            for i, c in enumerate(result.classifications):
                log(f"Doc {i+1}: {c.doc_type} | {c.sender} | {c.date} | ref:{c.reference}")

        log("Output files:")
        for f in result.output_files:
            log(f"-> {f}")

    # Exit with error code if there were issues
    sys.exit(1 if result.errors else 0)


if __name__ == "__main__":
    main()
