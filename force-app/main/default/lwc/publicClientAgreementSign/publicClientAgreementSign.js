import { LightningElement, track } from 'lwc';
// import getAgreementByToken from '@salesforce/apex/ClientAgreementPublicController.getAgreementByToken';
import getAgreementById from '@salesforce/apex/ClientAgreementPublicController.getAgreementById';
import submitSignature from '@salesforce/apex/ClientAgreementPublicController.submitSignature';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import AreliaSiteRedirectUrlLabel from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';

import JSPDF from '@salesforce/resourceUrl/jspdfs';

export default class PublicClientAgreementSign extends LightningElement {
    @track isLoading = true;
    @track isSubmitting = false;
    @track isValid = false;
    @track message;

    token;
    agreementId;
    agreementHtml;
    clientEmail;
    supervisorEmail;
    supportingFiles = [];
    errorMessage;
    errorDetails;
    drawing = false;
    hasSignature = false;
    scriptsLoaded = false;

    get hasError() {
        return this.errorMessage || this.errorDetails;
    }

    async connectedCallback() {
        try {
            this.clearError();

            // Token based flow is currently disabled.
            // this.token = this.getTokenFromUrl();

            this.agreementId = this.getAgreementIdFromUrl();

            await this.loadLibraries();
            await this.loadAgreement();
        } catch (error) {
            this.message = this.extractErrorMessage(error);
            this.isValid = false;
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    renderedCallback() {
        this.renderAgreement();
        this.initCanvas();
    }

    async loadLibraries() {
        if (this.scriptsLoaded) {
            return;
        }

        try {
            console.log('Loading jsPDF static resource:', JSPDF);

            await loadScript(this, JSPDF);

            console.log('jsPDF loaded:', window.jspdf || window.jsPDF);

            const jsPdfConstructor = this.getJsPdfConstructor();

            if (!jsPdfConstructor) {
                throw new Error('jsPDF library loaded but jsPDF constructor is not available.');
            }

            this.scriptsLoaded = true;
        } catch (error) {
            throw new Error(
                'Failed to load jsPDF library. Check Static Resource name: jspdfs. Original error: ' +
                this.extractErrorMessage(error)
            );
        }
    }

    getAgreementIdFromUrl() {
        const params = new URLSearchParams(window.location.search);
        return params.get('id');
    }

    async loadAgreement() {
        const result = await getAgreementById({
            agreementId: this.agreementId
        });

        if (!result) {
            throw new Error('No response received from getAgreementById.');
        }

        this.isValid = result.valid;
        this.message = result.message;

        this.agreementHtml = this.sanitizeAgreementHtml(result.agreementHtml);
        this.clientEmail = result.clientEmail;
        this.supervisorEmail = result.supervisorEmail;
        this.supportingFiles = result.supportingFiles || [];

        console.log('PUBLIC SUPPORTING FILES:', JSON.stringify(this.supportingFiles));

        console.log('Agreement loaded:', {
            isValid: this.isValid,
            message: this.message,
            clientEmail: this.clientEmail,
            supervisorEmail: this.supervisorEmail,
            agreementHtmlLength: this.agreementHtml ? this.agreementHtml.length : 0,
            supportingFilesCount: this.supportingFiles ? this.supportingFiles.length : 0
        });
    }

    renderAgreement() {
        const preview = this.template.querySelector('.agreement-preview');

        if (preview && this.agreementHtml) {
            preview.innerHTML =
                this.applyAgreementProfessionalStyles(this.agreementHtml) +
                this.buildSupportingImagesHtml(this.supportingFiles);
        }
    }

    buildSupportingImagesHtml(supportingFiles = []) {
        const imageFiles = (supportingFiles || []).filter(
            (file) => file && file.isImage && file.base64Data
        );

        if (!imageFiles.length) {
            return '';
        }

        let html = `
            <div style="
                margin-top: 34px;
                padding-top: 24px;
                border-top: 2px solid #d4af37;
            ">
                <h2 style="
                    margin: 0 0 18px;
                    color: #111111;
                    font-size: 20px;
                    font-weight: 800;
                    letter-spacing: 0.04em;
                    text-transform: uppercase;
                ">
                    Supporting Images / Exhibits
                </h2>
        `;

        imageFiles.forEach((file, index) => {
            html += `
                <div style="
                    margin-top: 18px;
                    padding: 16px;
                    border: 1px solid #d9c994;
                    border-radius: 10px;
                    background: #fffdf5;
                ">
                    <p style="
                        margin: 0 0 12px;
                        color: #8a6514;
                        font-size: 13px;
                        font-weight: 800;
                        letter-spacing: 0.04em;
                        text-transform: uppercase;
                    ">
                        Image ${index + 1}: ${this.escapeHtml(file.fileName)}
                    </p>

                    <img
                        src="data:${file.contentType};base64,${file.base64Data}"
                        style="
                            display: block;
                            max-width: 100%;
                            height: auto;
                            border: 1px solid #d9c994;
                            border-radius: 8px;
                            background: #ffffff;
                        "
                    />
                </div>
            `;
        });

        html += '</div>';

        return html;
    }

    initCanvas() {
        const canvas = this.template.querySelector('.signature-canvas');

        if (!canvas || canvas.dataset.initialized === 'true') {
            return;
        }

        const ctx = canvas.getContext('2d');
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.strokeStyle = '#000000';

        canvas.dataset.initialized = 'true';
    }

    getCanvasPosition(event) {
        const canvas = this.template.querySelector('.signature-canvas');
        const rect = canvas.getBoundingClientRect();

        let clientX;
        let clientY;

        if (event.touches && event.touches.length > 0) {
            clientX = event.touches[0].clientX;
            clientY = event.touches[0].clientY;
        } else {
            clientX = event.clientX;
            clientY = event.clientY;
        }

        return {
            x: clientX - rect.left,
            y: clientY - rect.top
        };
    }

    startDrawing(event) {
        event.preventDefault();

        const canvas = this.template.querySelector('.signature-canvas');
        const ctx = canvas.getContext('2d');
        const pos = this.getCanvasPosition(event);

        this.drawing = true;
        ctx.beginPath();
        ctx.moveTo(pos.x, pos.y);
    }

    draw(event) {
        if (!this.drawing) {
            return;
        }

        event.preventDefault();

        const canvas = this.template.querySelector('.signature-canvas');
        const ctx = canvas.getContext('2d');
        const pos = this.getCanvasPosition(event);

        ctx.lineTo(pos.x, pos.y);
        ctx.stroke();

        this.hasSignature = true;
    }

    stopDrawing(event) {
        if (event) {
            event.preventDefault();
        }

        this.drawing = false;
    }

    clearSignature() {
        this.clearError();

        const canvas = this.template.querySelector('.signature-canvas');

        if (!canvas) {
            this.showError(new Error('Signature canvas not found.'));
            return;
        }

        const ctx = canvas.getContext('2d');

        ctx.clearRect(0, 0, canvas.width, canvas.height);
        this.hasSignature = false;
    }

    async handleDone() {
        this.clearError();

        if (this.isSubmitting) {
            return;
        }

        if (!this.hasSignature) {
            this.showToast('Signature Required', 'Please sign before clicking Done.', 'warning');
            return;
        }

        this.isSubmitting = true;

        await this.waitForUiToRender();

        try {
            const canvas = this.template.querySelector('.signature-canvas');

            if (!canvas) {
                throw new Error('Signature canvas not found.');
            }

            const signatureBase64 = canvas.toDataURL('image/png');

            if (!signatureBase64) {
                throw new Error('Signature image is blank.');
            }

            const signedHtml = this.buildSignedAgreementHtml();

            if (!signedHtml) {
                throw new Error('Signed agreement HTML is blank.');
            }

            const signedPdfBase64 = await this.generatePdfBase64(
                signedHtml,
                signatureBase64,
                this.supportingFiles
            );

            if (!signedPdfBase64) {
                throw new Error('Signed PDF Base64 is blank.');
            }

            await submitSignature({
                agreementId: this.agreementId,
                signatureBase64: signatureBase64,
                signedAgreementHtml: signedHtml,
                signedPdfBase64: signedPdfBase64
            });

            this.isValid = false;
            this.message = 'Thank you. Your signed agreement has been submitted successfully.';

            this.showToast(
                'Signed',
                'Agreement submitted successfully.',
                'success'
            );
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    handleSubmittedOk() {
        const redirectUrl = (AreliaSiteRedirectUrlLabel || '').trim();

        if (redirectUrl) {
            window.location.assign(redirectUrl);
        }
    }

    buildSignedAgreementHtml() {
        const cleanAgreementHtml = this.sanitizeAgreementHtml(this.agreementHtml);

        const signedBlock = `
            <hr/>
            <h2>Digital Signature</h2>
            <p><strong>Client Email:</strong> ${this.escapeHtml(this.clientEmail)}</p>
            <p><strong>Supervisor Email:</strong> ${this.escapeHtml(this.supervisorEmail)}</p>
            <p><strong>Signed Date:</strong> ${new Date().toLocaleString()}</p>
            <p><strong>Signature captured electronically.</strong></p>
        `;

        return `
            <div class="agreement-document">
                ${cleanAgreementHtml}
                ${signedBlock}
            </div>
        `;
    }

    async generatePdfBase64(html, signatureBase64, supportingFiles = []) {
        const jsPdfConstructor = this.getJsPdfConstructor();

        if (!jsPdfConstructor) {
            throw new Error('jsPDF library is not loaded.');
        }

        if (!html) {
            throw new Error('Signed agreement HTML is blank.');
        }

        try {
            const pdf = new jsPdfConstructor('p', 'pt', 'a4');

            const ctx = this.createPdfContext(pdf);

            this.addPdfBrandHeader(ctx);
            this.renderAgreementHtmlToPdf(ctx, html);

            const agreementImageFiles = this.getAgreementImageFiles(html, supportingFiles);

            ctx.y = this.addSupportingImagesToPdf(
                pdf,
                agreementImageFiles,
                ctx.y,
                ctx.pageWidth,
                ctx.pageHeight,
                ctx.marginLeft,
                ctx.marginTop,
                ctx.usableWidth
            );

            this.addSignatureImageToPdf(ctx, signatureBase64);

            return pdf.output('datauristring');
        } catch (error) {
            throw new Error(
                'Failed to create signed PDF using jsPDF. Original error: ' +
                this.extractErrorMessage(error)
            );
        }
    }

    createPdfContext(pdf) {
        const pageWidth = pdf.internal.pageSize.getWidth();
        const pageHeight = pdf.internal.pageSize.getHeight();

        return {
            pdf,
            pageWidth,
            pageHeight,
            marginLeft: 48,
            marginRight: 48,
            marginTop: 48,
            marginBottom: 50,
            usableWidth: pageWidth - 96,
            y: 48,
            blue: [31, 78, 121],
            lightBlue: [91, 155, 213],
            body: [34, 34, 34],
            grey: [120, 120, 120],
            tableHeader: [243, 246, 250]
        };
    }

    addPdfBrandHeader(ctx) {
        const pdf = ctx.pdf;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(28);
        pdf.setTextColor(...ctx.blue);
        pdf.text('ARELIA SPACE', ctx.pageWidth / 2, ctx.y + 28, {
            align: 'center'
        });

        ctx.y += 46;

        pdf.setDrawColor(...ctx.lightBlue);
        pdf.setLineWidth(1.2);
        pdf.line(ctx.marginLeft, ctx.y, ctx.pageWidth - ctx.marginRight, ctx.y);

        ctx.y += 34;
    }

    addPdfSmallPageHeader(ctx) {
        const pdf = ctx.pdf;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(10);
        pdf.setTextColor(...ctx.grey);
        pdf.text('ARELIA SPACE', ctx.pageWidth / 2, 28, {
            align: 'center'
        });

        pdf.setDrawColor(220, 220, 220);
        pdf.setLineWidth(0.5);
        pdf.line(ctx.marginLeft, 38, ctx.pageWidth - ctx.marginRight, 38);
    }

    ensurePdfSpace(ctx, requiredHeight) {
        if (ctx.y + requiredHeight <= ctx.pageHeight - ctx.marginBottom) {
            return;
        }

        ctx.pdf.addPage();
        this.addPdfSmallPageHeader(ctx);
        ctx.y = ctx.marginTop + 18;
    }

    addPdfMainTitle(ctx, text) {
        if (!text) {
            return;
        }

        this.ensurePdfSpace(ctx, 45);

        const pdf = ctx.pdf;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(15);
        pdf.setTextColor(...ctx.blue);

        const lines = pdf.splitTextToSize(text.toUpperCase(), ctx.usableWidth);

        lines.forEach((line) => {
            pdf.text(line, ctx.marginLeft, ctx.y);
            ctx.y += 18;
        });

        ctx.y += 10;
    }

    addPdfSectionHeading(ctx, text) {
        if (!text) {
            return;
        }

        this.ensurePdfSpace(ctx, 36);

        const pdf = ctx.pdf;

        ctx.y += 10;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(12);
        pdf.setTextColor(...ctx.lightBlue);

        const lines = pdf.splitTextToSize(text.toUpperCase(), ctx.usableWidth);

        lines.forEach((line) => {
            pdf.text(line, ctx.marginLeft, ctx.y);
            ctx.y += 15;
        });

        ctx.y += 8;
    }

    addPdfParagraph(ctx, text) {
        if (!text) {
            return;
        }

        const cleanedText = this.cleanPdfText(text);

        if (!cleanedText) {
            return;
        }

        const pdf = ctx.pdf;

        pdf.setFont('helvetica', 'normal');
        pdf.setFontSize(10.5);
        pdf.setTextColor(...ctx.body);

        const lines = pdf.splitTextToSize(cleanedText, ctx.usableWidth);
        const requiredHeight = lines.length * 14 + 8;

        this.ensurePdfSpace(ctx, requiredHeight);

        lines.forEach((line) => {
            pdf.text(line, ctx.marginLeft, ctx.y);
            ctx.y += 14;
        });

        ctx.y += 8;
    }

    addPdfBullet(ctx, text) {
        if (!text) {
            return;
        }

        const cleanedText = this.cleanPdfText(text);

        if (!cleanedText) {
            return;
        }

        const pdf = ctx.pdf;

        pdf.setFont('helvetica', 'normal');
        pdf.setFontSize(10.5);
        pdf.setTextColor(...ctx.body);

        const bulletIndent = 14;
        const textX = ctx.marginLeft + bulletIndent;
        const lines = pdf.splitTextToSize(cleanedText, ctx.usableWidth - bulletIndent);
        const requiredHeight = lines.length * 14 + 4;

        this.ensurePdfSpace(ctx, requiredHeight);

        pdf.text('•', ctx.marginLeft, ctx.y);
        pdf.text(lines[0], textX, ctx.y);
        ctx.y += 14;

        for (let i = 1; i < lines.length; i++) {
            pdf.text(lines[i], textX, ctx.y);
            ctx.y += 14;
        }

        ctx.y += 4;
    }

    addPdfTable(ctx, rows) {
        if (!rows || !rows.length) {
            return;
        }

        const pdf = ctx.pdf;
        const colCount = Math.max(...rows.map((row) => row.cells.length));
        const tableWidth = ctx.usableWidth;

        let colWidths = [];

        if (colCount === 2) {
            colWidths = [tableWidth * 0.35, tableWidth * 0.65];
        } else {
            const equalWidth = tableWidth / colCount;
            for (let i = 0; i < colCount; i++) {
                colWidths.push(equalWidth);
            }
        }

        ctx.y += 4;

        rows.forEach((row) => {
            const cellLines = [];
            let rowHeight = 0;

            for (let i = 0; i < colCount; i++) {
                const cellText = row.cells[i] ? this.cleanPdfText(row.cells[i]) : '';
                const availableWidth = colWidths[i] - 12;
                const lines = pdf.splitTextToSize(cellText, availableWidth);

                cellLines.push(lines);

                const height = Math.max(24, lines.length * 12 + 12);

                if (height > rowHeight) {
                    rowHeight = height;
                }
            }

            this.ensurePdfSpace(ctx, rowHeight + 8);

            let x = ctx.marginLeft;

            for (let i = 0; i < colCount; i++) {
                if (row.isHeader) {
                    pdf.setFillColor(...ctx.tableHeader);
                    pdf.rect(x, ctx.y, colWidths[i], rowHeight, 'F');
                }

                pdf.setDrawColor(200, 200, 200);
                pdf.setLineWidth(0.5);
                pdf.rect(x, ctx.y, colWidths[i], rowHeight);

                pdf.setFont('helvetica', row.isHeader ? 'bold' : 'normal');
                pdf.setFontSize(9.5);
                pdf.setTextColor(...ctx.body);

                let textY = ctx.y + 15;

                cellLines[i].forEach((line) => {
                    pdf.text(line, x + 6, textY);
                    textY += 12;
                });

                x += colWidths[i];
            }

            ctx.y += rowHeight;
        });

        ctx.y += 14;
    }

    renderAgreementHtmlToPdf(ctx, html) {
        const elements = this.extractPdfElementsFromHtml(html);

        elements.forEach((element) => {
            if (!element || (!element.text && element.type !== 'table')) {
                return;
            }

            if (element.type !== 'table') {
                const text = this.cleanPdfText(element.text);

                if (!text) {
                    return;
                }

                if (text.toUpperCase() === 'ARELIA SPACE') {
                    return;
                }

                if (/^CLIENT SIGNATURE:\s*PENDING$/i.test(text)) {
                    return;
                }
            }

            if (element.type === 'mainTitle') {
                this.addPdfMainTitle(ctx, element.text);
            } else if (element.type === 'heading') {
                this.addPdfSectionHeading(ctx, element.text);
            } else if (element.type === 'bullet') {
                this.addPdfBullet(ctx, element.text);
            } else if (element.type === 'table') {
                this.addPdfTable(ctx, element.rows);
            } else {
                this.addPdfParagraph(ctx, element.text);
            }
        });
    }

    extractPdfElementsFromHtml(html) {
        const container = document.createElement('div');
        container.innerHTML = html || '';

        container.querySelectorAll('script, style, iframe, object, embed, img').forEach((node) => {
            node.remove();
        });

        const elements = [];

        const walk = (node) => {
            if (!node) {
                return;
            }

            if (node.nodeType === Node.TEXT_NODE) {
                const text = this.cleanPdfText(node.textContent);

                if (text) {
                    elements.push({
                        type: 'paragraph',
                        text
                    });
                }

                return;
            }

            if (node.nodeType !== Node.ELEMENT_NODE) {
                return;
            }

            const tag = node.tagName.toLowerCase();

            if (tag === 'h1') {
                elements.push({
                    type: 'mainTitle',
                    text: node.textContent
                });
                return;
            }

            if (tag === 'h2' || tag === 'h3') {
                elements.push({
                    type: 'heading',
                    text: node.textContent
                });
                return;
            }

            if (tag === 'p') {
                elements.push({
                    type: 'paragraph',
                    text: node.textContent
                });
                return;
            }

            if (tag === 'li') {
                elements.push({
                    type: 'bullet',
                    text: node.textContent
                });
                return;
            }

            if (tag === 'table') {
                const rows = this.extractTableRows(node);

                if (rows.length) {
                    elements.push({
                        type: 'table',
                        rows
                    });
                }

                return;
            }

            if (tag === 'br' || tag === 'hr') {
                return;
            }

            Array.from(node.childNodes).forEach((child) => {
                walk(child);
            });
        };

        Array.from(container.childNodes).forEach((child) => {
            walk(child);
        });

        return elements;
    }

    extractTableRows(tableNode) {
        const rows = [];

        tableNode.querySelectorAll('tr').forEach((tr) => {
            const cells = [];
            let isHeader = false;

            tr.querySelectorAll('th, td').forEach((cell) => {
                if (cell.tagName.toLowerCase() === 'th') {
                    isHeader = true;
                }

                cells.push(this.cleanPdfText(cell.textContent));
            });

            if (cells.length) {
                rows.push({
                    cells,
                    isHeader
                });
            }
        });

        return rows;
    }

    addSignatureImageToPdf(ctx, signatureBase64) {
        if (!signatureBase64) {
            return;
        }

        const pdf = ctx.pdf;

        this.ensurePdfSpace(ctx, 140);

        ctx.y += 18;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(12);
        pdf.setTextColor(...ctx.lightBlue);
        pdf.text('CLIENT SIGNATURE', ctx.marginLeft, ctx.y);

        ctx.y += 16;

        pdf.setDrawColor(200, 200, 200);
        pdf.rect(ctx.marginLeft, ctx.y, 240, 92);

        try {
            pdf.addImage(
                signatureBase64,
                'PNG',
                ctx.marginLeft + 10,
                ctx.y + 8,
                220,
                76
            );
        } catch (e) {
            pdf.setFont('helvetica', 'normal');
            pdf.setFontSize(10);
            pdf.setTextColor(...ctx.body);
            pdf.text('Unable to render signature image.', ctx.marginLeft + 10, ctx.y + 30);
        }

        ctx.y += 110;
    }

    cleanPdfText(value) {
        if (!value) {
            return '';
        }

        return String(value)
            .replace(/\u00a0/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    }

    addSupportingImagesToPdf(
        pdf,
        supportingFiles,
        y,
        pageWidth,
        pageHeight,
        marginLeft,
        marginTop,
        usableWidth
    ) {
        const imageFiles = (supportingFiles || []).filter(
            (file) => file && file.isImage && file.base64Data
        );

        if (!imageFiles.length) {
            return y;
        }

        if (y > pageHeight - 100) {
            pdf.addPage();
            y = marginTop;
        }

        y += 20;
        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(13);
        pdf.text('Supporting Images / Exhibits', marginLeft, y);
        y += 20;

        imageFiles.forEach((file, index) => {
            const imageData = `data:${file.contentType};base64,${file.base64Data}`;
            const imageFormat = file.contentType === 'image/png' ? 'PNG' : 'JPEG';

            const imageWidth = Math.min(usableWidth, 420);
            const imageHeight = 220;

            if (y > pageHeight - imageHeight - 50) {
                pdf.addPage();
                y = marginTop;
            }

            pdf.setFont('helvetica', 'bold');
            pdf.setFontSize(10);
            pdf.text(`Image ${index + 1}: ${file.fileName}`, marginLeft, y);
            y += 12;

            try {
                pdf.addImage(
                    imageData,
                    imageFormat,
                    marginLeft,
                    y,
                    imageWidth,
                    imageHeight
                );

                y += imageHeight + 20;
            } catch (e) {
                pdf.setFont('helvetica', 'normal');
                pdf.setFontSize(10);
                pdf.text(`Unable to render image: ${file.fileName}`, marginLeft, y);
                y += 20;
            }
        });

        return y;
    }

    sanitizeAgreementHtml(html) {
        if (!html) {
            return '';
        }

        let cleaned = html;

        cleaned = cleaned.replace(/<img[^>]+src=["']data:[^"']+["'][^>]*>/gi, '');
        cleaned = cleaned.replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, '');
        cleaned = cleaned.replace(/<style[\s\S]*?>[\s\S]*?<\/style>/gi, '');
        cleaned = cleaned.replace(/<iframe[\s\S]*?>[\s\S]*?<\/iframe>/gi, '');
        cleaned = cleaned.replace(/<object[\s\S]*?>[\s\S]*?<\/object>/gi, '');
        cleaned = cleaned.replace(/<embed[\s\S]*?>/gi, '');

        return cleaned;
    }

    htmlToPlainText(html) {
        if (!html) {
            return '';
        }

        let text = html;

        text = text.replace(/<img[^>]*>/gi, '');
        text = text.replace(/<br\s*\/?>/gi, '\n');
        text = text.replace(/<\/p>/gi, '\n\n');
        text = text.replace(/<\/div>/gi, '\n');
        text = text.replace(/<\/h1>/gi, '\n\n');
        text = text.replace(/<\/h2>/gi, '\n\n');
        text = text.replace(/<\/h3>/gi, '\n\n');
        text = text.replace(/<li>/gi, '• ');
        text = text.replace(/<\/li>/gi, '\n');
        text = text.replace(/<[^>]+>/g, '');

        const textarea = document.createElement('textarea');
        textarea.innerHTML = text;
        text = textarea.value;

        text = text.replace(/\n{3,}/g, '\n\n');

        return text.trim();
    }

    getJsPdfConstructor() {
        if (window.jspdf && window.jspdf.jsPDF) {
            return window.jspdf.jsPDF;
        }

        if (window.jsPDF) {
            return window.jsPDF;
        }

        return null;
    }

    clearError() {
        this.errorMessage = null;
        this.errorDetails = null;
    }

    showError(error) {
        console.error('Full public signing error:', error);

        const message = this.extractErrorMessage(error);
        const details = this.extractErrorDetails(error);

        this.errorMessage = message || 'Unknown error';
        this.errorDetails = details;

        this.showToast('Error', this.errorMessage, 'error');
    }

    extractError(error) {
        return this.extractErrorMessage(error);
    }

    extractErrorMessage(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (typeof error === 'string') {
            return error;
        }

        if (error.body) {
            if (typeof error.body.message === 'string') {
                return error.body.message;
            }

            if (Array.isArray(error.body)) {
                return error.body.map((e) => e.message).join(', ');
            }

            if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                return error.body.pageErrors.map((e) => e.message).join(', ');
            }

            if (error.body.output && error.body.output.errors && error.body.output.errors.length > 0) {
                return error.body.output.errors.map((e) => e.message).join(', ');
            }
        }

        if (error.message) {
            return error.message;
        }

        try {
            return JSON.stringify(error);
        } catch (e) {
            return 'Unknown error';
        }
    }

    extractErrorDetails(error) {
        if (!error) {
            return '';
        }

        let details = '';

        try {
            details += 'Raw Error:\n' + JSON.stringify(error, null, 2) + '\n\n';

            if (error.body) {
                if (error.body.exceptionType) {
                    details += 'Exception Type:\n' + error.body.exceptionType + '\n\n';
                }

                if (error.body.stackTrace) {
                    details += 'Stack Trace:\n' + error.body.stackTrace + '\n\n';
                }

                if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                    details += 'Page Errors:\n' +
                        error.body.pageErrors.map((e) => e.message).join('\n') +
                        '\n\n';
                }

                if (error.body.fieldErrors) {
                    details += 'Field Errors:\n' +
                        JSON.stringify(error.body.fieldErrors, null, 2) +
                        '\n\n';
                }

                if (error.body.output) {
                    details += 'Output:\n' +
                        JSON.stringify(error.body.output, null, 2) +
                        '\n\n';
                }
            }

            if (error.stack) {
                details += 'JavaScript Stack:\n' + error.stack;
            }
        } catch (e) {
            details = '';
        }

        return details;
    }

    escapeHtml(value) {
        if (!value) {
            return '';
        }

        return String(value)
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#39;');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    applyAgreementProfessionalStyles(html) {
        if (!html) {
            return '';
        }

        const container = document.createElement('div');
        container.innerHTML = html;

        const root = container.querySelector('.agreement-document') || container;

        root.style.fontFamily = 'Aptos, Inter, Segoe UI, Arial, Helvetica, sans-serif';
        root.style.color = '#111111';
        root.style.lineHeight = '1.65';
        root.style.background = '#ffffff';

        const h1List = root.querySelectorAll('h1');
        h1List.forEach((h1) => {
            const text = (h1.textContent || '').trim().toUpperCase();

            if (text === 'ARELIA SPACE') {
                h1.style.textAlign = 'center';
                h1.style.fontSize = '34px';
                h1.style.fontWeight = '900';
                h1.style.color = '#ffdf73';
                h1.style.letterSpacing = '4px';
                h1.style.margin = '0 0 22px 0';
                h1.style.padding = '22px 18px 20px';
                h1.style.border = '1px solid #d4af37';
                h1.style.borderBottom = '4px solid #d4af37';
                h1.style.background = 'linear-gradient(145deg, #050505, #151515)';
                h1.style.WebkitTextFillColor = '#ffdf73';
                h1.style.textTransform = 'uppercase';
            } else {
                h1.style.fontSize = '20px';
                h1.style.color = '#111111';
                h1.style.textTransform = 'uppercase';
                h1.style.marginTop = '28px';
                h1.style.marginBottom = '18px';
                h1.style.fontWeight = '900';
                h1.style.letterSpacing = '0.04em';
                h1.style.paddingBottom = '10px';
                h1.style.borderBottom = '2px solid #d4af37';
            }
        });

        const h2List = root.querySelectorAll('h2');
        h2List.forEach((h2) => {
            h2.style.fontSize = '16px';
            h2.style.color = '#8a6514';
            h2.style.textTransform = 'uppercase';
            h2.style.marginTop = '30px';
            h2.style.marginBottom = '12px';
            h2.style.fontWeight = '900';
            h2.style.letterSpacing = '0.05em';
            h2.style.padding = '10px 12px';
            h2.style.borderLeft = '4px solid #d4af37';
            h2.style.background = '#fff8e1';
        });

        const h3List = root.querySelectorAll('h3');
        h3List.forEach((h3) => {
            h3.style.fontSize = '15px';
            h3.style.color = '#111111';
            h3.style.textTransform = 'uppercase';
            h3.style.marginTop = '24px';
            h3.style.marginBottom = '10px';
            h3.style.fontWeight = '900';
            h3.style.letterSpacing = '0.04em';
        });

        const pList = root.querySelectorAll('p');
        pList.forEach((p) => {
            p.style.fontSize = '14px';
            p.style.color = '#1c1c1c';
            p.style.marginTop = '8px';
            p.style.marginBottom = '10px';
            p.style.lineHeight = '1.65';
        });

        const tableList = root.querySelectorAll('table');
        tableList.forEach((table) => {
            table.style.width = '100%';
            table.style.borderCollapse = 'collapse';
            table.style.marginTop = '14px';
            table.style.marginBottom = '26px';
            table.style.border = '1px solid #d9c994';
            table.style.background = '#ffffff';
        });

        const trList = root.querySelectorAll('tr');
        trList.forEach((tr, index) => {
            tr.style.background = index % 2 === 0 ? '#ffffff' : '#fffdf5';
        });

        const tdList = root.querySelectorAll('td');
        tdList.forEach((td, index) => {
            td.style.border = '1px solid #e5d8aa';
            td.style.padding = '10px 12px';
            td.style.fontSize = '14px';
            td.style.verticalAlign = 'top';
            td.style.color = '#111111';
            td.style.lineHeight = '1.55';

            if (index % 2 === 0) {
                td.style.fontWeight = '800';
                td.style.color = '#111111';
                td.style.background = '#fff8e1';
                td.style.width = '34%';
            }
        });

        const thList = root.querySelectorAll('th');
        thList.forEach((th) => {
            th.style.border = '1px solid #d4af37';
            th.style.padding = '11px 12px';
            th.style.textAlign = 'left';
            th.style.background = 'linear-gradient(145deg, #050505, #151515)';
            th.style.color = '#ffdf73';
            th.style.fontSize = '13px';
            th.style.fontWeight = '900';
            th.style.letterSpacing = '0.04em';
            th.style.textTransform = 'uppercase';
        });

        const ulList = root.querySelectorAll('ul');
        ulList.forEach((ul) => {
            ul.style.marginTop = '8px';
            ul.style.marginBottom = '16px';
            ul.style.paddingLeft = '24px';
        });

        const liList = root.querySelectorAll('li');
        liList.forEach((li) => {
            li.style.fontSize = '14px';
            li.style.marginBottom = '7px';
            li.style.lineHeight = '1.6';
            li.style.color = '#1c1c1c';
        });

        const hrList = root.querySelectorAll('hr');
        hrList.forEach((hr) => {
            hr.style.border = 'none';
            hr.style.borderTop = '2px solid #d4af37';
            hr.style.margin = '28px 0';
        });

        const imgList = root.querySelectorAll('img');
        imgList.forEach((img) => {
            img.style.maxWidth = '100%';
            img.style.height = 'auto';
            img.style.border = '1px solid #d9c994';
            img.style.borderRadius = '8px';
            img.style.marginTop = '10px';
            img.style.marginBottom = '14px';
            img.style.background = '#ffffff';
        });

        return container.innerHTML;
    }

    waitForUiToRender() {
        return new Promise((resolve) => {
            window.requestAnimationFrame(() => {
                window.requestAnimationFrame(resolve);
            });
        });
    }

    getAgreementImageFiles(html, supportingFiles = []) {
        const imageFiles = (supportingFiles || []).filter(
            (file) => file && file.isImage && file.base64Data
        );

        if (!html || !imageFiles.length) {
            return [];
        }

        return imageFiles.filter((file) => {
            return this.isFileReferencedInAgreementHtml(file, html);
        });
    }

    getSeparateAttachmentFiles(html, supportingFiles = []) {
        return (supportingFiles || []).filter((file) => {
            if (!file) {
                return false;
            }

            if (file.isPdf === true) {
                return true;
            }

            if (file.isImage === true) {
                return !this.isFileReferencedInAgreementHtml(file, html);
            }

            return false;
        });
    }

    isFileReferencedInAgreementHtml(file, html) {
        if (!file || !html) {
            return false;
        }

        const candidates = this.getFileIdCandidates(file);

        return candidates.some((candidate) => html.includes(candidate));
    }

    getFileIdCandidates(file) {
        const candidates = [];

        if (file.contentDocumentId) {
            candidates.push(file.contentDocumentId);

            if (file.contentDocumentId.length >= 15) {
                candidates.push(file.contentDocumentId.substring(0, 15));
            }
        }

        if (file.contentVersionId) {
            candidates.push(file.contentVersionId);

            if (file.contentVersionId.length >= 15) {
                candidates.push(file.contentVersionId.substring(0, 15));
            }
        }

        return candidates;
    }
}