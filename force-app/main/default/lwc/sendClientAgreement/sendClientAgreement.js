import { LightningElement, api, track } from 'lwc';
import getAgreementInitData from '@salesforce/apex/ClientAgreementInternalController.getAgreementInitData';
import sendAgreementToClient from '@salesforce/apex/ClientAgreementInternalController.sendAgreementToClient';
import getOpportunitySupportingFiles from '@salesforce/apex/ClientAgreementInternalController.getOpportunitySupportingFiles';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { loadScript } from 'lightning/platformResourceLoader';

import JSPDF from '@salesforce/resourceUrl/jspdfs';
// import HTML2CANVAS from '@salesforce/resourceUrl/html2canvas';

export default class SendClientAgreement extends LightningElement {
    @api recordId;

    @track clientEmail;
    @track supervisorEmail;
    @track agreementHtml;

    isLoading = true;
    isSending = false;
    isEditing = false;
    scriptsLoaded = false;
    uploadedSupportingDocumentIds = [];
    // removedSupportingDocumentIds = [];
    errorMessage;
    errorDetails;

    @track supportingFiles = [];

    get saveDisabled() {
        return !this.isEditing;
    }

    get hasError() {
        return this.errorMessage || this.errorDetails;
    }

    async connectedCallback() {
        try {
            this.clearError();

            await this.loadLibraries();
            await this.loadInitData();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    renderedCallback() {
        this.renderPreview();
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
                throw new Error(
                    'jsPDF library loaded but jsPDF constructor is not available. Check the jspdf static resource file.'
                );
            }

            this.scriptsLoaded = true;
        } catch (error) {
            console.error('Library loading failed:', error);

            throw new Error(
                'Failed to load jsPDF library. Please check Static Resource name: jspdf. Original error: ' +
                this.extractErrorMessage(error)
            );
        }
    }

    async loadInitData() {
        if (!this.recordId) {
            throw new Error('Opportunity recordId is missing.');
        }

        const result = await getAgreementInitData({
            opportunityId: this.recordId
        });

        if (!result) {
            throw new Error('No response received from getAgreementInitData.');
        }

        this.clientEmail = result.clientEmail;
        this.supervisorEmail = result.supervisorEmail;
        this.agreementHtml = result.agreementHtml;

        // this.supportingFiles = result.supportingFiles || [];

        this.supportingFiles = this.prepareSupportingFiles(result.supportingFiles || []);

        if (!this.clientEmail) {
            throw new Error('Client Email is blank.');
        }

        if (!this.supervisorEmail) {
            throw new Error('Supervisor Email is blank.');
        }

        if (!this.agreementHtml) {
            throw new Error('Agreement HTML is blank.');
        }
    }

    // renderPreview() {
    //     const preview = this.template.querySelector('.preview-box');

    //     if (preview && this.agreementHtml && !this.isEditing) {
    //         /*
    //         * Preview shows only agreement/rich-text images.
    //         * File-upload-section images/PDFs are supporting attachments.
    //         */
    //         preview.innerHTML =
    //             this.applyAgreementProfessionalStyles(this.agreementHtml) +
    //             this.buildSupportingImagesHtml(
    //                 this.getAgreementImageFiles(this.agreementHtml, this.supportingFiles)
    //             );
    //     }
    // }

    renderPreview() {
        const preview = this.template.querySelector('.preview-box');

        if (preview && this.agreementHtml && !this.isEditing) {
            /*
            * Preview shows only agreement/rich-text images.
            * File-upload-section images/PDFs are supporting attachments.
            */
            preview.innerHTML =
                this.applyAgreementProfessionalStyles(this.agreementHtml) +
                this.buildSupportingImagesHtml(
                    this.getAgreementImageFiles(this.supportingFiles)
                );
        }
    }

    handleEdit() {
        this.clearError();
        this.isEditing = true;
    }

    handleAgreementChange(event) {
        this.agreementHtml = event.target.value;
    }

    

    handleSave() {
        this.clearError();

        /*
        * Re-apply professional formatting after lightning-input-rich-text
        * normalizes/sanitizes the HTML.
        */

        this.agreementHtml = this.applyAgreementProfessionalStyles(this.agreementHtml);

        // this.agreementHtml = this.buildProfessionalAgreementDisplayHtml(this.agreementHtml);

        this.isEditing = false;

        this.showToast(
            'Saved',
            'Agreement text saved in the modal.',
            'success'
        );
    }

    async handleSend() {
        this.isSending = true;
        this.isLoading = true;
        this.clearError();

        try {
            console.log('Send clicked.');
            console.log('Opportunity recordId:', this.recordId);
            console.log('Client Email:', this.clientEmail);
            console.log('Supervisor Email:', this.supervisorEmail);
            console.log('Agreement HTML length:', this.agreementHtml ? this.agreementHtml.length : 0);
            console.log('Checking jspdf:', window.jspdf);
            console.log('Checking jsPDF:', window.jsPDF);

            if (!this.recordId) {
                throw new Error('Opportunity recordId is missing.');
            }

            if (!this.agreementHtml) {
                throw new Error('Agreement HTML is blank. Please enter agreement text before sending.');
            }

            /*
            * Refresh latest Opportunity files before generating PDF/sending email.
            * Removed files remain excluded because selectedSupportingFiles filters them out.
            */
            await this.refreshSupportingFilesOnly();

            console.log('All supporting files:', this.supportingFiles);
            console.log('Selected supporting files:', this.selectedSupportingFiles);
            console.log('Selected supporting document Ids:', this.selectedSupportingDocumentIds);

            /*
            * Only selected image files are included inside generated agreement PDF.
            * PDF supporting files are not embedded inside the generated agreement PDF.
            * They are sent separately as email attachments.
            */
            const pdfBase64 = await this.generatePdfBase64(
                this.agreementHtml
            );

            console.log('PDF generated successfully. Length:', pdfBase64 ? pdfBase64.length : 0);

            if (!pdfBase64) {
                throw new Error('PDF generation returned blank content.');
            }

            /*
            * Pass only selected files.
            * Removed files are excluded from this list.
            * Selected PDFs/images are sent as separate attachments.
            */
            await sendAgreementToClient({
                opportunityId: this.recordId,
                agreementHtml: this.agreementHtml,
                pdfBase64: pdfBase64,
                separateAttachmentContentDocumentIds: this.selectedSupportingDocumentIds
            });

            this.showToast(
                'Agreement Sent',
                'Client agreement has been sent to the client.',
                'success'
            );

            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSending = false;
            this.isLoading = false;
        }
    }

    async generatePdfBase64(html, supportingFiles = []) {
        const jsPdfConstructor = this.getJsPdfConstructor();

        if (!jsPdfConstructor) {
            throw new Error('jsPDF library is not loaded.');
        }

        if (!html) {
            throw new Error('Agreement HTML is blank.');
        }

        try {
            const pdf = new jsPdfConstructor('p', 'pt', 'a4');

            const ctx = this.createPdfContext(pdf);

            this.addPdfBrandHeader(ctx);
            this.renderAgreementHtmlToPdf(ctx, html);

            /*
            * Do not embed uploaded supporting JPG/PNG files into the PDF.
            * They are already sent separately as email attachments through Apex.
            *
            * This prevents the pdfBase64 request from becoming too large and
            * failing before sendAgreementToClient reaches Apex.
            */

            const dataUri = pdf.output('datauristring');

            if (!dataUri || !dataUri.includes(',')) {
                throw new Error('PDF generation returned invalid Base64 content.');
            }

            return dataUri.substring(dataUri.indexOf(',') + 1);

        } catch (error) {
            throw new Error(
                'Failed to create PDF using jsPDF. Original error: ' +
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
            if (!element || !element.text && element.type !== 'table') {
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

    cleanPdfText(value) {
        if (!value) {
            return '';
        }

        return String(value)
            .replace(/\u00a0/g, ' ')
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

    clearError() {
        this.errorMessage = null;
        this.errorDetails = null;
    }

    showError(error) {
        console.error('Full error object:', error);

        let message = this.extractErrorMessage(error);
        let details = this.extractErrorDetails(error);

        if (!message) {
            message = 'Unknown error';
        }

        this.errorMessage = message;
        this.errorDetails = details;

        this.showToast('Error', message, 'error');
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

            if (!details && error.stack) {
                details += 'JavaScript Stack:\n' + error.stack;
            }

            if (!details) {
                details = JSON.stringify(error, null, 2);
            }
        } catch (e) {
            details = '';
        }

        return details;
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

    htmlToPlainText(html) {
        if (!html) {
            return '';
        }

        let text = html;

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

    get acceptedFormats() {
        return [
            '.png',
            '.jpg',
            '.jpeg',
            '.pdf',
            'image/png',
            'image/jpeg',
            'application/pdf'
        ];
    }

    get hasSupportingFiles() {
        return this.selectedSupportingFiles && this.selectedSupportingFiles.length > 0;
    }

    // async handleUploadFinished(event) {
    //     this.clearError();

    //     const uploadedFiles = event.detail.files || [];

    //     this.showToast(
    //         'Files Uploaded',
    //         uploadedFiles.length + ' supporting file(s) uploaded.',
    //         'success'
    //     );

    //     /*
    //     * Force fresh reload from Apex after upload.
    //     */
    //     this.supportingFiles = [];

    //     await this.loadInitData();

    //     console.log('Supporting files after upload:', {
    //         count: this.supportingFiles ? this.supportingFiles.length : 0,
    //         files: this.supportingFiles
    //     });

    //     this.renderPreview();
    // }

    async handleUploadFinished(event) {
        this.clearError();

        const uploadedFiles = event.detail.files || [];

        uploadedFiles.forEach((file) => {
            if (file.documentId && !this.uploadedSupportingDocumentIds.includes(file.documentId)) {
                this.uploadedSupportingDocumentIds.push(file.documentId);
            }

            /*
            * If the same document Id was previously removed, allow it again after upload.
            */

            // if (file.documentId && this.removedSupportingDocumentIds.includes(file.documentId)) {
            //     this.removedSupportingDocumentIds = this.removedSupportingDocumentIds.filter(
            //         (documentId) => documentId !== file.documentId
            //     );
            // }
        });

        this.showToast(
            'Files Uploaded',
            uploadedFiles.length + ' supporting file(s) uploaded.',
            'success'
        );

        await this.refreshSupportingFilesOnly();

        console.log('Uploaded supporting document Ids:', this.uploadedSupportingDocumentIds);
        // console.log('Removed supporting document Ids:', this.removedSupportingDocumentIds);
        console.log('Selected supporting document Ids:', this.selectedSupportingDocumentIds);

        this.renderPreview();
    }

    // handleRemoveSupportingFile(event) {
    //     this.clearError();

    //     const documentId = event.currentTarget.dataset.documentId;

    //     if (!documentId) {
    //         return;
    //     }

    //     if (!this.removedSupportingDocumentIds.includes(documentId)) {
    //         this.removedSupportingDocumentIds = [
    //             ...this.removedSupportingDocumentIds,
    //             documentId
    //         ];
    //     }

    //     this.uploadedSupportingDocumentIds = this.uploadedSupportingDocumentIds.filter(
    //         (uploadedDocumentId) => uploadedDocumentId !== documentId
    //     );

    //     this.showToast(
    //         'File Removed',
    //         'The file has been removed from this agreement. It was not deleted from Salesforce Files.',
    //         'success'
    //     );

    //     this.renderPreview();
    // }

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
        const imageFiles = (supportingFiles || []).filter((file) => file && file.isImage && file.base64Data);

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

    buildSupportingImagesHtml(supportingFiles = []) {
        const imageFiles = (supportingFiles || []).filter(
            (file) => file && file.isImage && file.base64Data
        );

        if (!imageFiles.length) {
            return '';
        }

        let html = '<hr/><h2>Supporting Images / Exhibits</h2>';

        imageFiles.forEach((file, index) => {
            html += `
                <div style="margin-top:12px;">
                    <p><strong>Image ${index + 1}:</strong> ${this.escapeHtml(file.fileName)}</p>
                    <img
                        src="data:${file.contentType};base64,${file.base64Data}"
                        style="max-width:100%; border:1px solid #cccccc;"
                    />
                </div>
            `;
        });

        return html;
    }

    escapeHtml(value) {
        if (!value) {
            return '';
        }

        return value
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#39;');
    }

    async refreshSupportingFilesOnly() {
        const files = await getOpportunitySupportingFiles({
            opportunityId: this.recordId
        });

        this.supportingFiles = this.prepareSupportingFiles(files || []);

        console.log('Fresh supporting files:', {
            count: this.supportingFiles.length,
            files: this.supportingFiles
        });
    }

    applyAgreementProfessionalStyles(html) {
        if (!html) {
            return '';
        }

        const container = document.createElement('div');
        container.innerHTML = html;

        const root = container.querySelector('.agreement-document') || container;

        root.style.fontFamily = 'Arial, Helvetica, sans-serif';
        root.style.color = '#222222';
        root.style.lineHeight = '1.55';

        const h1List = root.querySelectorAll('h1');
        h1List.forEach((h1) => {
            const text = (h1.textContent || '').trim().toUpperCase();

            if (text === 'ARELIA SPACE') {
                h1.style.textAlign = 'center';
                h1.style.fontSize = '34px';
                h1.style.fontWeight = '700';
                h1.style.color = '#1f4e79';
                h1.style.letterSpacing = '1px';
                h1.style.margin = '0 0 18px 0';
                h1.style.paddingBottom = '16px';
                h1.style.borderBottom = '2px solid #5b9bd5';
            } else {
                h1.style.fontSize = '20px';
                h1.style.color = '#1f4e79';
                h1.style.textTransform = 'uppercase';
                h1.style.marginTop = '24px';
                h1.style.marginBottom = '22px';
                h1.style.fontWeight = '500';
            }
        });

        const h2List = root.querySelectorAll('h2');
        h2List.forEach((h2) => {
            h2.style.fontSize = '16px';
            h2.style.color = '#5b9bd5';
            h2.style.textTransform = 'uppercase';
            h2.style.marginTop = '30px';
            h2.style.marginBottom = '12px';
            h2.style.fontWeight = '700';
        });

    const pList = root.querySelectorAll('p');
        pList.forEach((p) => {
            p.style.fontSize = '14px';
            p.style.color = '#222222';
            p.style.marginTop = '8px';
            p.style.marginBottom = '10px';
            p.style.lineHeight = '1.55';
        });

        const tableList = root.querySelectorAll('table');
        tableList.forEach((table) => {
            table.style.width = '100%';
            table.style.borderCollapse = 'collapse';
            table.style.marginTop = '8px';
            table.style.marginBottom = '24px';
        });

        const tdList = root.querySelectorAll('td');
        tdList.forEach((td) => {
            td.style.padding = '6px 8px';
            td.style.fontSize = '14px';
            td.style.verticalAlign = 'top';
        });

        const thList = root.querySelectorAll('th');
        thList.forEach((th) => {
            th.style.border = '1px solid #cccccc';
            th.style.padding = '8px';
            th.style.textAlign = 'left';
            th.style.background = '#f3f6fa';
            th.style.fontSize = '14px';
            th.style.fontWeight = '700';
        });

        const ulList = root.querySelectorAll('ul');
        ulList.forEach((ul) => {
            ul.style.marginTop = '4px';
            ul.style.marginBottom = '14px';
            ul.style.paddingLeft = '24px';
        });

        const liList = root.querySelectorAll('li');
        liList.forEach((li) => {
            li.style.fontSize = '14px';
            li.style.marginBottom = '6px';
            li.style.lineHeight = '1.5';
        });

        const imgList = root.querySelectorAll('img');
        imgList.forEach((img) => {
            img.style.maxWidth = '100%';
            img.style.border = '1px solid #cccccc';
            img.style.marginTop = '8px';
            img.style.marginBottom = '12px';
        });

        return container.innerHTML;
    }

    // getAgreementImageFiles(html, supportingFiles = []) {
    //     const imageFiles = (supportingFiles || []).filter(
    //         (file) => file && file.isImage && file.base64Data
    //     );

    //     if (!html || !imageFiles.length) {
    //         return [];
    //     }

    //     return imageFiles.filter((file) => {
    //         return this.isFileReferencedInAgreementHtml(file, html);
    //     });
    // }

    // getSeparateAttachmentFiles(html, supportingFiles = []) {
    //     return (supportingFiles || []).filter((file) => {
    //         if (!file) {
    //             return false;
    //         }

    //         if (file.isPdf === true) {
    //             return true;
    //         }

    //         if (file.isImage === true) {
    //             return !this.isFileReferencedInAgreementHtml(file, html);
    //         }

    //         return false;
    //     });
    // }

    // isFileReferencedInAgreementHtml(file, html) {
    //     if (!file || !html) {
    //         return false;
    //     }

    //     const candidates = this.getFileIdCandidates(file);

    //     return candidates.some((candidate) => html.includes(candidate));
    // }

    // getFileIdCandidates(file) {
    //     const candidates = [];

    //     if (file.contentDocumentId) {
    //         candidates.push(file.contentDocumentId);

    //         if (file.contentDocumentId.length >= 15) {
    //             candidates.push(file.contentDocumentId.substring(0, 15));
    //         }
    //     }

    //     if (file.contentVersionId) {
    //         candidates.push(file.contentVersionId);

    //         if (file.contentVersionId.length >= 15) {
    //             candidates.push(file.contentVersionId.substring(0, 15));
    //         }
    //     }

    //     return candidates;
    // }

    getAgreementImageFiles(supportingFiles = []) {
        return (supportingFiles || []).filter((file) => {
            if (!file || file.isImage !== true || !file.base64Data) {
                return false;
            }

            /*
            * File-upload-section images are sent as separate attachments.
            * They should not be embedded into agreement PDF.
            */
            if (file.contentDocumentId
                && this.uploadedSupportingDocumentIds.includes(file.contentDocumentId)) {
                return false;
            }

            return true;
        });
    }

    getSeparateAttachmentFiles(supportingFiles = []) {
        return (supportingFiles || []).filter((file) => {
            if (!file) {
                return false;
            }

            return file.contentDocumentId
                && this.uploadedSupportingDocumentIds.includes(file.contentDocumentId);
        });
    }

    // get selectedSupportingFiles() {
    //     return (this.supportingFiles || []).filter((file) => {
    //         const documentId = this.getFileDocumentId(file);
    //         return documentId && !this.removedSupportingDocumentIds.includes(documentId);
    //     });
    // }

    get selectedSupportingFiles() {
        return (this.supportingFiles || []).filter((file) => {
            return this.getFileDocumentId(file);
        });
    }

    get selectedSupportingDocumentIds() {
        return this.selectedSupportingFiles
            .map((file) => this.getFileDocumentId(file))
            .filter((documentId) => documentId);
    }

    prepareSupportingFiles(files = []) {
        return (files || []).map((file, index) => {
            const documentId = this.getFileDocumentId(file);

            return {
                ...file,
                uiKey: documentId || file.contentVersionId || `${file.fileName}-${index}`,
                displayType: file.isPdf ? 'PDF' : file.isImage ? 'Image' : 'File'
            };
        });
    }

    getFileDocumentId(file) {
        if (!file) {
            return null;
        }

        return file.contentDocumentId || null;
    }
}