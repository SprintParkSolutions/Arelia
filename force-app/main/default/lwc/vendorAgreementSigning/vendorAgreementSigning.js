import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';

import JSPDF from '@salesforce/resourceUrl/jspdfs';

import getAgreementById
    from '@salesforce/apex/VendorAgreementSigningService.getAgreementById';

import signAgreement
    from '@salesforce/apex/VendorAgreementSigningService.signAgreement';

import REDIRECT_URL
    from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';

export default class VendorAgreementSigning extends LightningElement {
    agreementId;
    agreementHtml = '';
    vendorName = '';
    isLoading = true;
    agreementLoaded = false;
    errorMessage = '';
    isDrawing = false;
    hasSignature = false;
    canvasContext;
    scriptsLoaded = false;
    showSuccessScreen = false;

    async connectedCallback() {
        try {
            const pageUrl = new URL(window.location.href);

            this.agreementId =
                pageUrl.searchParams.get('agreementId');

            await this.loadPdfLibrary();
            await this.loadAgreement();
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    renderedCallback() {
        if (this.agreementLoaded && !this.canvasContext) {
            const canvas = this.template.querySelector('canvas');

            if (canvas) {
                this.canvasContext = canvas.getContext('2d');
                this.canvasContext.lineWidth = 2;
                this.canvasContext.lineCap = 'round';
            }
        }
    }

    async loadPdfLibrary() {
        if (this.scriptsLoaded) {
            return;
        }

        await loadScript(this, JSPDF);

        if (!this.getJsPdfConstructor()) {
            throw new Error(
                'jsPDF library could not be loaded.'
            );
        }

        this.scriptsLoaded = true;
    }

    // async loadAgreement() {
    //     if (!this.agreementId) {
    //         throw new Error('Agreement Id is missing.');
    //     }

    //     const response = await getAgreementById({
    //         agreementId: this.agreementId
    //     });

    //     this.agreementHtml = response.agreementHtml;
    //     this.vendorName = response.vendorName;
    //     this.agreementLoaded = true;
    // }

    async loadAgreement() {
        if (!this.agreementId) {
            throw new Error('Agreement Id is missing.');
        }

        const response = await getAgreementById({
            agreementId: this.agreementId
        });

        this.agreementHtml = response.agreementHtml;
        this.vendorName = response.vendorName;
        this.showSuccessScreen = false;
        this.agreementLoaded = true;
    }

    startDrawing(event) {
        event.preventDefault();

        this.isDrawing = true;

        const position = this.getCoordinates(event);

        this.canvasContext.beginPath();
        this.canvasContext.moveTo(position.x, position.y);
    }

    draw(event) {
        if (!this.isDrawing) {
            return;
        }

        event.preventDefault();

        const position = this.getCoordinates(event);

        this.canvasContext.lineTo(position.x, position.y);
        this.canvasContext.stroke();

        this.hasSignature = true;
    }

    stopDrawing() {
        this.isDrawing = false;
    }

    clearSignature() {
        const canvas = this.template.querySelector('canvas');

        if (!canvas || !this.canvasContext) {
            return;
        }

        this.canvasContext.clearRect(
            0,
            0,
            canvas.width,
            canvas.height
        );

        this.hasSignature = false;
    }

    getCoordinates(event) {
        const canvas = this.template.querySelector('canvas');
        const rectangle = canvas.getBoundingClientRect();

        const touch =
            event.touches && event.touches.length > 0
                ? event.touches[0]
                : event;

        return {
            x: touch.clientX - rectangle.left,
            y: touch.clientY - rectangle.top
        };
    }

    async handleDone() {
        if (!this.hasSignature) {
            this.showToast(
                'Signature Required',
                'Please provide your digital signature before continuing.',
                'error'
            );

            return;
        }

        const canvas = this.template.querySelector('canvas');

        if (!canvas) {
            this.showToast(
                'Error',
                'Signature area could not be loaded.',
                'error'
            );

            return;
        }

        try {
            this.isLoading = true;

            const signatureBase64 =
                canvas.toDataURL('image/png');

            const signedPdfBase64 =
                this.generateSignedPdfBase64(
                    signatureBase64
                );

            await signAgreement({
                agreementId: this.agreementId,
                signatureBase64,
                signedPdfBase64
            });

            // this.agreementLoaded = false;

            // this.showToast(
            //     'Success',
            //     'Your signed Vendor Agreement has been submitted.',
            //     'success'
            // );

            this.agreementLoaded = false;
            this.showSuccessScreen = true;
            this.errorMessage = '';
            this.canvasContext = null;
            this.hasSignature = false;

        } catch (error) {
            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    generateSignedPdfBase64(signatureBase64) {
        const JsPdfConstructor = this.getJsPdfConstructor();

        if (!JsPdfConstructor) {
            throw new Error('jsPDF library is unavailable.');
        }

        const pdf = new JsPdfConstructor('p', 'pt', 'a4');

        const ctx = {
            pdf,
            pageWidth: pdf.internal.pageSize.getWidth(),
            pageHeight: pdf.internal.pageSize.getHeight(),
            marginLeft: 46,
            marginRight: 46,
            marginTop: 52,
            marginBottom: 50,
            y: 52
        };

        ctx.usableWidth = ctx.pageWidth - ctx.marginLeft - ctx.marginRight;

        this.addSignedPdfHeader(ctx);
        this.renderAgreementHtmlToSignedPdf(ctx, this.agreementHtml);
        this.addVendorSignatureToPdf(ctx, signatureBase64);

        return pdf.output('datauristring');
    }

    addSignedPdfHeader(ctx) {
        const pdf = ctx.pdf;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(24);
        pdf.setTextColor(31, 78, 121);
        pdf.text('ARELIA SPACE', ctx.pageWidth / 2, ctx.y + 24, {
            align: 'center'
        });

        ctx.y += 46;

        pdf.setFontSize(17);
        pdf.setTextColor(17, 24, 39);
        pdf.text('SIGNED VENDOR AGREEMENT', ctx.pageWidth / 2, ctx.y, {
            align: 'center'
        });

        ctx.y += 26;

        pdf.setFont('helvetica', 'normal');
        pdf.setFontSize(10);
        pdf.setTextColor(90, 100, 115);
        pdf.text(
            'Interior Design Vendor / Contractor Agreement',
            ctx.pageWidth / 2,
            ctx.y,
            { align: 'center' }
        );

        ctx.y += 26;

        pdf.setDrawColor(31, 78, 121);
        pdf.setLineWidth(1.4);
        pdf.line(ctx.marginLeft, ctx.y, ctx.pageWidth - ctx.marginRight, ctx.y);

        ctx.y += 28;
    }

    renderAgreementHtmlToSignedPdf(ctx, html) {
        const container = document.createElement('div');
        container.innerHTML = html || '';

        container
            .querySelectorAll('script, style, iframe, object, embed, img')
            .forEach((node) => node.remove());

        this.renderSignedPdfContentInOrder(ctx, container);
    }

    renderReferenceTable(ctx, container) {
        const table = container.querySelector('table');

        if (!table) {
            return;
        }

        const rows = [];

        table.querySelectorAll('tr').forEach((tr) => {
            const cells = Array.from(tr.querySelectorAll('td, th'))
                .map((cell) => this.cleanPdfText(cell.textContent));

            if (cells.length >= 2) {
                rows.push({
                    label: cells[0],
                    value: cells[1]
                });
            }
        });

        if (!rows.length) {
            return;
        }

        const pdf = ctx.pdf;
        const labelWidth = 170;
        const valueWidth = ctx.usableWidth - labelWidth;
        const rowHeight = 31;

        rows.forEach((row) => {
            this.ensureSignedPdfSpace(ctx, rowHeight + 4);

            pdf.setDrawColor(197, 208, 222);
            pdf.setLineWidth(0.7);

            pdf.setFillColor(232, 240, 248);
            pdf.rect(ctx.marginLeft, ctx.y, labelWidth, rowHeight, 'FD');

            pdf.setFillColor(255, 255, 255);
            pdf.rect(ctx.marginLeft + labelWidth, ctx.y, valueWidth, rowHeight, 'FD');

            pdf.setFont('helvetica', 'bold');
            pdf.setFontSize(10);
            pdf.setTextColor(22, 71, 116);
            pdf.text(row.label, ctx.marginLeft + 8, ctx.y + 20);

            pdf.setFont('helvetica', 'normal');
            pdf.setTextColor(31, 41, 55);
            pdf.text(
                pdf.splitTextToSize(row.value, valueWidth - 14),
                ctx.marginLeft + labelWidth + 8,
                ctx.y + 20
            );

            ctx.y += rowHeight;
        });

        ctx.y += 22;
    }

    renderAgreementSections(ctx, container) {
        const nodes = Array.from(container.querySelectorAll('h1, h2, h3, p, li'));

        nodes.forEach((node) => {
            const tag = node.tagName.toLowerCase();
            const text = this.cleanPdfText(node.textContent);

            if (!text) {
                return;
            }

            if (text.toUpperCase() === 'ARELIA SPACE') {
                return;
            }

            if (text.toUpperCase() === 'VENDOR AGREEMENT') {
                return;
            }

            if (text.toLowerCase().includes('interior design vendor')) {
                return;
            }

            if (tag === 'h1' || tag === 'h2' || tag === 'h3') {
                this.addSignedPdfSectionHeading(ctx, text);
            } else if (tag === 'li') {
                this.addSignedPdfBullet(ctx, text);
            } else {
                this.addSignedPdfParagraph(ctx, text);
            }
        });
    }

    addSignedPdfSectionHeading(ctx, text) {
        const pdf = ctx.pdf;

        this.ensureSignedPdfSpace(ctx, 34);

        ctx.y += 8;

        pdf.setFillColor(31, 78, 121);
        pdf.rect(ctx.marginLeft, ctx.y - 13, 4, 18, 'F');

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(12);
        pdf.setTextColor(31, 78, 121);

        const lines = pdf.splitTextToSize(text, ctx.usableWidth - 14);

        lines.forEach((line) => {
            pdf.text(line, ctx.marginLeft + 12, ctx.y);
            ctx.y += 15;
        });

        ctx.y += 7;
    }

    addSignedPdfParagraph(ctx, text) {
        const pdf = ctx.pdf;

        const lines = pdf.splitTextToSize(text, ctx.usableWidth);
        const requiredHeight = lines.length * 13 + 8;

        this.ensureSignedPdfSpace(ctx, requiredHeight);

        pdf.setFont('helvetica', 'normal');
        pdf.setFontSize(10);
        pdf.setTextColor(31, 41, 55);

        lines.forEach((line) => {
            pdf.text(line, ctx.marginLeft, ctx.y);
            ctx.y += 13;
        });

        ctx.y += 7;
    }

    addSignedPdfBullet(ctx, text) {
        const pdf = ctx.pdf;

        const bulletIndent = 14;
        const lines = pdf.splitTextToSize(text, ctx.usableWidth - bulletIndent);
        const requiredHeight = lines.length * 13 + 5;

        this.ensureSignedPdfSpace(ctx, requiredHeight);

        pdf.setFont('helvetica', 'normal');
        pdf.setFontSize(10);
        pdf.setTextColor(31, 41, 55);

        pdf.text('•', ctx.marginLeft + 6, ctx.y);
        pdf.text(lines[0], ctx.marginLeft + bulletIndent, ctx.y);

        ctx.y += 13;

        for (let i = 1; i < lines.length; i++) {
            pdf.text(lines[i], ctx.marginLeft + bulletIndent, ctx.y);
            ctx.y += 13;
        }

        ctx.y += 4;
    }

    addVendorSignatureToPdf(ctx, signatureBase64) {
        const pdf = ctx.pdf;

        this.ensureSignedPdfSpace(ctx, 170);

        ctx.y += 16;

        pdf.setDrawColor(31, 78, 121);
        pdf.setLineWidth(1);
        pdf.line(ctx.marginLeft, ctx.y, ctx.pageWidth - ctx.marginRight, ctx.y);

        ctx.y += 28;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(13);
        pdf.setTextColor(31, 78, 121);
        pdf.text('VENDOR DIGITAL SIGNATURE', ctx.marginLeft, ctx.y);

        ctx.y += 20;

        pdf.setFont('helvetica', 'normal');
        pdf.setFontSize(10);
        pdf.setTextColor(31, 41, 55);

        pdf.text(`Vendor: ${this.vendorName || ''}`, ctx.marginLeft, ctx.y);
        ctx.y += 16;

        pdf.text(`Signed Date: ${new Date().toLocaleString()}`, ctx.marginLeft, ctx.y);
        ctx.y += 18;

        pdf.setDrawColor(200, 200, 200);
        pdf.rect(ctx.marginLeft, ctx.y, 250, 92);

        pdf.addImage(
            signatureBase64,
            'PNG',
            ctx.marginLeft + 10,
            ctx.y + 8,
            225,
            76
        );

        ctx.y += 112;

        pdf.setFontSize(9);
        pdf.setTextColor(90, 100, 115);
        pdf.text(
            'This agreement was signed electronically by the vendor.',
            ctx.marginLeft,
            ctx.y
        );
    }

    ensureSignedPdfSpace(ctx, requiredHeight) {
        if (ctx.y + requiredHeight <= ctx.pageHeight - ctx.marginBottom) {
            return;
        }

        ctx.pdf.addPage();
        this.addSignedPdfPageHeader(ctx);
        ctx.y = ctx.marginTop + 24;
    }

    addSignedPdfPageHeader(ctx) {
        const pdf = ctx.pdf;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(9);
        pdf.setTextColor(90, 100, 115);
        pdf.text('ARELIA SPACE - SIGNED VENDOR AGREEMENT', ctx.pageWidth / 2, 28, {
            align: 'center'
        });

        pdf.setDrawColor(220, 220, 220);
        pdf.line(ctx.marginLeft, 38, ctx.pageWidth - ctx.marginRight, 38);
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

    htmlToPlainText(htmlValue) {
        const container = document.createElement('div');

        container.innerHTML = htmlValue || '';

        return (container.textContent || '')
            .replace(/\s+/g, ' ')
            .trim();
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

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    getErrorMessage(error) {
        return error?.body?.message
            || error?.message
            || 'An unexpected error occurred.';
    }

    renderAllAgreementTables(ctx, container) {
        const tables = Array.from(container.querySelectorAll('table'));

        tables.forEach((table) => {
            const rows = [];

            table.querySelectorAll('tr').forEach((tr) => {
                const cells = Array.from(tr.querySelectorAll('td, th'))
                    .map((cell) => this.cleanPdfText(cell.textContent));

                if (cells.length >= 2) {
                    rows.push({
                        label: cells[0],
                        value: cells[1]
                    });
                }
            });

            if (!rows.length) {
                return;
            }

            const pdf = ctx.pdf;
            const labelWidth = 170;
            const valueWidth = ctx.usableWidth - labelWidth;
            const rowHeight = 30;

            rows.forEach((row) => {
                this.ensureSignedPdfSpace(ctx, rowHeight + 4);

                pdf.setDrawColor(197, 208, 222);
                pdf.setLineWidth(0.7);

                pdf.setFillColor(232, 240, 248);
                pdf.rect(ctx.marginLeft, ctx.y, labelWidth, rowHeight, 'FD');

                pdf.setFillColor(255, 255, 255);
                pdf.rect(
                    ctx.marginLeft + labelWidth,
                    ctx.y,
                    valueWidth,
                    rowHeight,
                    'FD'
                );

                pdf.setFont('helvetica', 'bold');
                pdf.setFontSize(9.5);
                pdf.setTextColor(22, 71, 116);
                pdf.text(row.label, ctx.marginLeft + 8, ctx.y + 19);

                pdf.setFont('helvetica', 'normal');
                pdf.setFontSize(9.5);
                pdf.setTextColor(31, 41, 55);

                const valueLines = pdf.splitTextToSize(
                    row.value || '',
                    valueWidth - 14
                );

                pdf.text(
                    valueLines,
                    ctx.marginLeft + labelWidth + 8,
                    ctx.y + 19
                );

                ctx.y += rowHeight;
            });

            ctx.y += 20;
        });
    }

    renderSignedPdfContentInOrder(ctx, container) {
        const nodes = Array.from(container.children);

        nodes.forEach((node) => {
            this.renderSignedPdfNode(ctx, node);
        });
    }

    renderSignedPdfNode(ctx, node) {
        if (!node || node.nodeType !== Node.ELEMENT_NODE) {
            return;
        }

        const tag = node.tagName.toLowerCase();

        if (tag === 'div') {
            const className = node.className || '';

            if (
                className.includes('agreement-header')
                || className.includes('agreement-footer')
            ) {
                return;
            }

            Array.from(node.children).forEach((child) => {
                this.renderSignedPdfNode(ctx, child);
            });

            return;
        }

        if (tag === 'table') {
            this.renderSingleAgreementTable(ctx, node);
            return;
        }

        const text = this.cleanPdfText(node.textContent);

        if (!text) {
            return;
        }

        if (text.toUpperCase() === 'ARELIA SPACE') {
            return;
        }

        if (text.toUpperCase() === 'VENDOR AGREEMENT') {
            return;
        }

        if (text.toLowerCase().includes('interior design vendor')) {
            return;
        }

        if (tag === 'h1' || tag === 'h2' || tag === 'h3') {
            this.addSignedPdfSectionHeading(ctx, text);
            return;
        }

        if (tag === 'p') {
            this.addSignedPdfParagraph(ctx, text);
            return;
        }

        if (tag === 'ul' || tag === 'ol') {
            node.querySelectorAll('li').forEach((li) => {
                this.addSignedPdfBullet(
                    ctx,
                    this.cleanPdfText(li.textContent)
                );
            });
            return;
        }

        if (tag === 'li') {
            this.addSignedPdfBullet(ctx, text);
        }
    }

    renderSingleAgreementTable(ctx, table) {
        const rows = [];

        table.querySelectorAll('tr').forEach((tr) => {
            const cells = Array.from(tr.querySelectorAll('td, th'))
                .map((cell) => this.cleanPdfText(cell.textContent));

            if (cells.length >= 2) {
                rows.push({
                    label: cells[0],
                    value: cells[1]
                });
            }
        });

        if (!rows.length) {
            return;
        }

        const pdf = ctx.pdf;
        const labelWidth = 170;
        const valueWidth = ctx.usableWidth - labelWidth;
        const rowHeight = 30;

        rows.forEach((row) => {
            this.ensureSignedPdfSpace(ctx, rowHeight + 4);

            pdf.setDrawColor(197, 208, 222);
            pdf.setLineWidth(0.7);

            pdf.setFillColor(232, 240, 248);
            pdf.rect(ctx.marginLeft, ctx.y, labelWidth, rowHeight, 'FD');

            pdf.setFillColor(255, 255, 255);
            pdf.rect(
                ctx.marginLeft + labelWidth,
                ctx.y,
                valueWidth,
                rowHeight,
                'FD'
            );

            pdf.setFont('helvetica', 'bold');
            pdf.setFontSize(9.5);
            pdf.setTextColor(22, 71, 116);
            pdf.text(row.label, ctx.marginLeft + 8, ctx.y + 19);

            pdf.setFont('helvetica', 'normal');
            pdf.setFontSize(9.5);
            pdf.setTextColor(31, 41, 55);

            const valueLines = pdf.splitTextToSize(
                row.value || '',
                valueWidth - 14
            );

            pdf.text(
                valueLines,
                ctx.marginLeft + labelWidth + 8,
                ctx.y + 19
            );

            ctx.y += rowHeight;
        });

        ctx.y += 20;
    }

    handleRedirect() {
        if (!REDIRECT_URL) {
            this.showToast(
                'Redirect URL Missing',
                'Redirect URL is not configured.',
                'error'
            );

            return;
        }

        window.location.assign(REDIRECT_URL);
    }
}