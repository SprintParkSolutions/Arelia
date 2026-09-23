import { LightningElement, api, track } from 'lwc';
import getAgreementInitData from '@salesforce/apex/ClientAgreementInternalController.getAgreementInitData';
import sendAgreementToClient from '@salesforce/apex/ClientAgreementInternalController.sendAgreementToClient';
import getOpportunitySupportingFiles from '@salesforce/apex/ClientAgreementInternalController.getOpportunitySupportingFiles';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { loadScript } from 'lightning/platformResourceLoader';

import JSPDF from '@salesforce/resourceUrl/jspdfs';
import ARELIA_LOGO from '@salesforce/resourceUrl/AreliaLogo';
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
    areliaLogoDataUrl;
    areliaLogoWidth;
    areliaLogoHeight;

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

            /*
            * Load jsPDF and the logo simultaneously.
            * This avoids sequential loading and minimizes any effect on loading time.
            */
            await Promise.all([
                loadScript(this, JSPDF),
                this.loadAreliaLogo()
            ]);

            console.log('jsPDF loaded:', window.jspdf || window.jsPDF);

            const jsPdfConstructor = this.getJsPdfConstructor();

            if (!jsPdfConstructor) {
                throw new Error(
                    'jsPDF library loaded but jsPDF constructor is not available. ' +
                    'Check the jspdf static resource file.'
                );
            }

            this.scriptsLoaded = true;
        } catch (error) {
            console.error('Library loading failed:', error);

            throw new Error(
                'Failed to load PDF resources. Original error: ' +
                this.extractErrorMessage(error)
            );
        }
    }

    loadAreliaLogo() {
        if (this.areliaLogoDataUrl) {
            return Promise.resolve();
        }

        return new Promise((resolve) => {
            const logoImage = new Image();

            /*
            * Prevent logo loading from keeping the component waiting indefinitely.
            */
            const timeoutId = window.setTimeout(() => {
                console.warn(
                    'Arelia logo loading timed out. Using text fallback.'
                );
                resolve();
            }, 5000);

            logoImage.onload = () => {
                window.clearTimeout(timeoutId);

                try {
                    /*
                    * Resize the source image before converting it to Base64.
                    * Do not use the original full-resolution dimensions because
                    * that increases PDF size and send time.
                    */
                    const maximumWidth = 480;
                    const maximumHeight = 180;

                    const sourceWidth =
                        logoImage.naturalWidth || logoImage.width;

                    const sourceHeight =
                        logoImage.naturalHeight || logoImage.height;

                    if (!sourceWidth || !sourceHeight) {
                        console.warn('Arelia logo has invalid dimensions.');
                        resolve();
                        return;
                    }

                    const scale = Math.min(
                        maximumWidth / sourceWidth,
                        maximumHeight / sourceHeight,
                        1
                    );

                    const targetWidth = Math.max(
                        1,
                        Math.round(sourceWidth * scale)
                    );

                    const targetHeight = Math.max(
                        1,
                        Math.round(sourceHeight * scale)
                    );

                    /*
                    * Store the actual optimized image dimensions so the PDF
                    * preserves the logo's original aspect ratio.
                    */
                    this.areliaLogoWidth = targetWidth;
                    this.areliaLogoHeight = targetHeight;

                    const canvas = document.createElement('canvas');
                    canvas.width = targetWidth;
                    canvas.height = targetHeight;

                    const context = canvas.getContext('2d');

                    if (!context) {
                        console.warn('Logo canvas context is unavailable.');
                        resolve();
                        return;
                    }

                    context.drawImage(
                        logoImage,
                        0,
                        0,
                        targetWidth,
                        targetHeight
                    );

                    /*
                    * Keep PNG so a transparent logo background remains transparent.
                    */
                    this.areliaLogoDataUrl =
                        canvas.toDataURL('image/png');

                    resolve();
                } catch (error) {
                    console.warn(
                        'Unable to optimize Arelia logo for PDF:',
                        error
                    );
                    resolve();
                }
            };

            logoImage.onerror = () => {
                window.clearTimeout(timeoutId);

                console.warn(
                    'Unable to load AreliaLogo. Using text fallback.'
                );

                resolve();
            };

            logoImage.src = ARELIA_LOGO;
        });
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

        // this.agreementHtml = this.applyAgreementProfessionalStyles(this.agreementHtml);

        const normalizedAgreementHtml =
            this.normalizeRichTextLists(
                this.agreementHtml
            );

        this.agreementHtml =
            this.applyAgreementProfessionalStyles(
                normalizedAgreementHtml
            );

        // this.agreementHtml = this.buildProfessionalAgreementDisplayHtml(this.agreementHtml);

        this.isEditing = false;

        this.showToast(
            'Saved',
            'Agreement text saved in the modal.',
            'success'
        );
    }

    normalizeRichTextLists(html) {
        if (!html) {
            return '';
        }

        const container = document.createElement('div');
        container.innerHTML = html;

        /*
        * Salesforce rich text can use data-list="bullet" and
        * data-list="ordered" instead of standard UL/OL structure.
        * Convert those items into normal HTML lists so that they
        * remain visible after Save and in manual previews.
        */
        const listContainers = Array.from(
            container.querySelectorAll('ul, ol')
        );

        listContainers.forEach((listContainer) => {
            const directListItems = Array.from(
                listContainer.children
            ).filter((child) => {
                return child.tagName &&
                    child.tagName.toLowerCase() === 'li';
            });

            if (!directListItems.length) {
                return;
            }

            const fragment = document.createDocumentFragment();
            let currentList = null;
            let currentListType = null;

            directListItems.forEach((listItem) => {
                const dataListValue = (
                    listItem.getAttribute('data-list') || ''
                ).toLowerCase();

                let requiredListType;

                if (dataListValue === 'bullet') {
                    requiredListType = 'ul';
                } else if (dataListValue === 'ordered') {
                    requiredListType = 'ol';
                } else {
                    requiredListType =
                        listContainer.tagName.toLowerCase();
                }

                if (
                    !currentList ||
                    currentListType !== requiredListType
                ) {
                    currentList =
                        document.createElement(
                            requiredListType
                        );

                    currentListType = requiredListType;
                    fragment.appendChild(currentList);
                }

                const normalizedListItem =
                    listItem.cloneNode(true);

                normalizedListItem.removeAttribute(
                    'data-list'
                );

                currentList.appendChild(
                    normalizedListItem
                );
            });

            listContainer.replaceWith(fragment);
        });

        return container.innerHTML;
    }

    async handleSend() {

        /*
        * Prevent multiple send requests when the user clicks Send repeatedly.
        */
        if (this.isSending) {
            return;
        }
        
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

        // const logoWidth = 112;
        // const logoHeight = 54;
        // const logoX = (ctx.pageWidth - logoWidth) / 2;
        // const logoY = ctx.y;

        if (this.areliaLogoDataUrl) {
            const maximumLogoWidth = 92;
            const maximumLogoHeight = 92;

            const logoDimensions = this.getPdfLogoDimensions(
                maximumLogoWidth,
                maximumLogoHeight
            );

            const logoX =
                (ctx.pageWidth - logoDimensions.width) / 2;

            pdf.addImage(
                this.areliaLogoDataUrl,
                'PNG',
                logoX,
                ctx.y,
                logoDimensions.width,
                logoDimensions.height,
                'ARELIA_LOGO',
                'FAST'
            );

            ctx.y += logoDimensions.height + 14;
        } else {
            pdf.setFont('helvetica', 'bold');
            pdf.setFontSize(28);
            pdf.setTextColor(...ctx.blue);

            pdf.text(
                'ARELIA SPACE',
                ctx.pageWidth / 2,
                ctx.y + 28,
                {
                    align: 'center'
                }
            );

            ctx.y += 46;
        }

        pdf.setDrawColor(...ctx.lightBlue);
        pdf.setLineWidth(1.2);

        pdf.line(
            ctx.marginLeft,
            ctx.y,
            ctx.pageWidth - ctx.marginRight,
            ctx.y
        );

        ctx.y += 28;
    }

    addPdfSmallPageHeader(ctx) {
        const pdf = ctx.pdf;

        if (this.areliaLogoDataUrl) {
            /*
            * Use the same maximum dimensions as the first-page logo.
            */
            const logoDimensions =
                this.getPdfLogoDimensions(92, 92);

            const logoX =
                (ctx.pageWidth - logoDimensions.width) / 2;

            const logoY = 18;

            pdf.addImage(
                this.areliaLogoDataUrl,
                'PNG',
                logoX,
                logoY,
                logoDimensions.width,
                logoDimensions.height,
                'ARELIA_LOGO',
                'FAST'
            );

            const dividerY =
                logoY + logoDimensions.height + 14;

            pdf.setDrawColor(...ctx.lightBlue);
            pdf.setLineWidth(1.2);

            pdf.line(
                ctx.marginLeft,
                dividerY,
                ctx.pageWidth - ctx.marginRight,
                dividerY
            );
        } else {
            pdf.setFont('helvetica', 'bold');
            pdf.setFontSize(28);
            pdf.setTextColor(...ctx.blue);

            pdf.text(
                'ARELIA SPACE',
                ctx.pageWidth / 2,
                46,
                {
                    align: 'center'
                }
            );

            pdf.setDrawColor(...ctx.lightBlue);
            pdf.setLineWidth(1.2);

            pdf.line(
                ctx.marginLeft,
                72,
                ctx.pageWidth - ctx.marginRight,
                72
            );
        }
    }

    ensurePdfSpace(ctx, requiredHeight) {
        if (ctx.y + requiredHeight <= ctx.pageHeight - ctx.marginBottom) {
            return;
        }

        ctx.pdf.addPage();
        this.addPdfSmallPageHeader(ctx);
        const logoDimensions =
            this.getPdfLogoDimensions(92, 92);

        ctx.y =
            18 +
            logoDimensions.height +
            14 +
            28;
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
        const elements =
            this.extractPdfElementsFromHtml(html);

        elements.forEach((element) => {
            if (!element) {
                return;
            }

            if (element.type === 'table') {
                this.addPdfTable(ctx, element.rows);
                return;
            }

            if (!element.runs || !element.runs.length) {
                return;
            }

            const plainText = element.runs
                .map((run) => run.text || '')
                .join('')
                .trim();

            if (!plainText) {
                return;
            }

            if (plainText.toUpperCase() === 'ARELIA SPACE') {
                return;
            }

            if (
                /^CLIENT SIGNATURE:\s*PENDING$/i.test(
                    plainText
                )
            ) {
                return;
            }

            this.addPdfRichTextBlock(ctx, element);
        });
    }

    extractPdfElementsFromHtml(html) {
        const container = document.createElement('div');
        container.innerHTML = html || '';

        container
            .querySelectorAll(
                'script, style, iframe, object, embed, img'
            )
            .forEach((node) => {
                node.remove();
            });

        const elements = [];

        const processBlock = (
            node,
            type,
            listMarker = ''
        ) => {
            const blockStyle =
                this.getPdfNodeStyle(node, {});

            const runs = [];

            this.collectPdfTextRuns(
                node,
                blockStyle,
                runs
            );

            if (listMarker) {
                runs.unshift({
                    text: listMarker,
                    bold: false,
                    italic: false,
                    underline: false,
                    strike: false,
                    fontFamily: 'helvetica',
                    fontSize: blockStyle.fontSize || 10.5,
                    link: null
                });
            }

            if (runs.some((run) => run.text && run.text.trim())) {
                elements.push({
                    type,
                    runs,
                    alignment: blockStyle.alignment,
                    indentLevel: blockStyle.indentLevel,
                    fontSize: blockStyle.fontSize
                });
            }
        };

        const walk = (node) => {
            if (
                !node ||
                node.nodeType !== Node.ELEMENT_NODE
            ) {
                return;
            }

            const tagName = node.tagName.toLowerCase();

            if (tagName === 'table') {
                const rows = this.extractTableRows(node);

                if (rows.length) {
                    elements.push({
                        type: 'table',
                        rows
                    });
                }

                return;
            }

            if (tagName === 'h1') {
                processBlock(node, 'mainTitle');
                return;
            }

            if (
                tagName === 'h2' ||
                tagName === 'h3'
            ) {
                processBlock(node, 'heading');
                return;
            }

            if (tagName === 'p') {
                processBlock(node, 'paragraph');
                return;
            }

            if (tagName === 'ul') {
                Array.from(node.children).forEach((child) => {
                    if (
                        child.tagName &&
                        child.tagName.toLowerCase() === 'li'
                    ) {
                        processBlock(
                            child,
                            'bullet',
                            '• '
                        );
                    }
                });

                return;
            }

            if (tagName === 'ol') {
                let itemNumber = 1;

                Array.from(node.children).forEach((child) => {
                    if (
                        child.tagName &&
                        child.tagName.toLowerCase() === 'li'
                    ) {
                        processBlock(
                            child,
                            'numbered',
                            `${itemNumber}. `
                        );

                        itemNumber += 1;
                    }
                });

                return;
            }

            if (tagName === 'li') {
                processBlock(
                    node,
                    'bullet',
                    '• '
                );
                return;
            }

            Array.from(node.children).forEach((child) => {
                walk(child);
            });
        };

        Array.from(container.children).forEach((child) => {
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

        // const container = document.createElement('div');
        // container.innerHTML = html;

        /*
        * Keep an untouched copy of the rich-text editor HTML.
        * Professional document styling is applied to a separate copy.
        */
        const originalContainer = document.createElement('div');
        originalContainer.innerHTML = html;

        const container = originalContainer.cloneNode(true);

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
            ul.style.marginTop = '8px';
            ul.style.marginBottom = '16px';
            ul.style.paddingLeft = '28px';
            ul.style.listStyleType = 'disc';
            ul.style.listStylePosition = 'outside';
        });

        const olList = root.querySelectorAll('ol');
        olList.forEach((ol) => {
            ol.style.marginTop = '8px';
            ol.style.marginBottom = '16px';
            ol.style.paddingLeft = '30px';
            ol.style.listStyleType = 'decimal';
            ol.style.listStylePosition = 'outside';
        });

        const liList = root.querySelectorAll('li');
        liList.forEach((li) => {
            li.style.display = 'list-item';
            li.style.fontSize = '14px';
            li.style.marginBottom = '7px';
            li.style.lineHeight = '1.6';
            li.style.color = '#1c1c1c';
        });

        const imgList = root.querySelectorAll('img');
        imgList.forEach((img) => {
            img.style.maxWidth = '100%';
            img.style.border = '1px solid #cccccc';
            img.style.marginTop = '8px';
            img.style.marginBottom = '12px';
        });

        /*
        * Reapply formatting explicitly selected in lightning-input-rich-text.
        * This prevents the professional default styles from overriding user edits.
        */
        this.restoreUserRichTextFormatting(
            originalContainer,
            container
        );

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

    getPdfLogoDimensions(maximumWidth, maximumHeight) {
        if (!this.areliaLogoWidth || !this.areliaLogoHeight) {
            return {
                width: maximumWidth,
                height: maximumHeight
            };
        }

        const scale = Math.min(
            maximumWidth / this.areliaLogoWidth,
            maximumHeight / this.areliaLogoHeight
        );

        return {
            width: this.areliaLogoWidth * scale,
            height: this.areliaLogoHeight * scale
        };
    }

    restoreUserRichTextFormatting(
        originalContainer,
        formattedContainer
    ) {
        if (!originalContainer || !formattedContainer) {
            return;
        }

        const originalElements =
            originalContainer.querySelectorAll('*');

        const formattedElements =
            formattedContainer.querySelectorAll('*');

        const supportedStyleProperties = [
            'font-family',
            'font-size',
            'font-weight',
            'font-style',
            'text-decoration',
            'text-align',
            'padding-left',
            'margin-left'
        ];

        const elementCount = Math.min(
            originalElements.length,
            formattedElements.length
        );

        for (let index = 0; index < elementCount; index += 1) {
            const originalElement = originalElements[index];
            const formattedElement = formattedElements[index];

            supportedStyleProperties.forEach((propertyName) => {
                const propertyValue =
                    originalElement.style.getPropertyValue(
                        propertyName
                    );

                if (propertyValue) {
                    formattedElement.style.setProperty(
                        propertyName,
                        propertyValue
                    );
                }
            });

            /*
            * Salesforce rich-text alignment and indentation can also
            * be represented by ql-* classes.
            */
            Array.from(originalElement.classList).forEach(
                (className) => {
                    if (
                        className.startsWith('ql-align-') ||
                        className.startsWith('ql-indent-') ||
                        className.startsWith('ql-size-') ||
                        className.startsWith('ql-font-')
                    ) {
                        formattedElement.classList.add(className);
                    }
                }
            );

            if (
                originalElement.tagName.toLowerCase() === 'a' &&
                originalElement.hasAttribute('href')
            ) {
                formattedElement.setAttribute(
                    'href',
                    originalElement.getAttribute('href')
                );

                formattedElement.setAttribute(
                    'target',
                    '_blank'
                );
            }
        }
    }

    collectPdfTextRuns(
        node,
        inheritedStyle,
        runs
    ) {
        if (!node) {
            return;
        }

        if (node.nodeType === Node.TEXT_NODE) {
            const text = String(node.textContent || '')
                .replace(/\u00a0/g, ' ')
                .replace(/\s+/g, ' ');

            if (text) {
                runs.push({
                    text,
                    bold: inheritedStyle.bold === true,
                    italic: inheritedStyle.italic === true,
                    underline:
                        inheritedStyle.underline === true,
                    strike:
                        inheritedStyle.strike === true,
                    fontFamily:
                        inheritedStyle.fontFamily ||
                        'helvetica',
                    fontSize:
                        inheritedStyle.fontSize ||
                        10.5,
                    link:
                        inheritedStyle.link || null,
                    color:
                        inheritedStyle.color ||
                        [34, 34, 34]
                });
            }

            return;
        }

        if (node.nodeType !== Node.ELEMENT_NODE) {
            return;
        }

        const tagName = node.tagName.toLowerCase();

        if (tagName === 'br') {
            runs.push({
                text: '\n',
                bold: inheritedStyle.bold === true,
                italic: inheritedStyle.italic === true,
                underline:
                    inheritedStyle.underline === true,
                strike:
                    inheritedStyle.strike === true,
                fontFamily:
                    inheritedStyle.fontFamily ||
                    'helvetica',
                fontSize:
                    inheritedStyle.fontSize ||
                    10.5,
                link:
                    inheritedStyle.link || null,
                color:
                    inheritedStyle.color ||
                    [34, 34, 34]
            });

            return;
        }

        const currentStyle =
            this.getPdfNodeStyle(
                node,
                inheritedStyle
            );

        Array.from(node.childNodes).forEach((child) => {
            this.collectPdfTextRuns(
                child,
                currentStyle,
                runs
            );
        });
    }

    getPdfNodeStyle(node, inheritedStyle = {}) {
        const style = {
            bold: inheritedStyle.bold === true,
            italic: inheritedStyle.italic === true,
            underline:
                inheritedStyle.underline === true,
            strike:
                inheritedStyle.strike === true,
            fontFamily:
                inheritedStyle.fontFamily ||
                'helvetica',
            fontSize:
                inheritedStyle.fontSize ||
                10.5,
            alignment:
                inheritedStyle.alignment ||
                'left',
            indentLevel:
                inheritedStyle.indentLevel || 0,
            link:
                inheritedStyle.link || null,
            color:
                inheritedStyle.color ||
                [34, 34, 34]
        };

        if (
            !node ||
            node.nodeType !== Node.ELEMENT_NODE
        ) {
            return style;
        }

        const tagName = node.tagName.toLowerCase();
        const inlineStyle = node.style;

        if (inlineStyle.color) {
            style.color =
                this.convertCssColorToPdfRgb(
                    inlineStyle.color,
                    style.color
                );
        }

        if (
            tagName === 'strong' ||
            tagName === 'b'
        ) {
            style.bold = true;
        }

        if (
            tagName === 'em' ||
            tagName === 'i'
        ) {
            style.italic = true;
        }

        if (tagName === 'u') {
            style.underline = true;
        }

        if (
            tagName === 's' ||
            tagName === 'strike' ||
            tagName === 'del'
        ) {
            style.strike = true;
        }

        if (
            tagName === 'a' &&
            node.getAttribute('href')
        ) {
            style.link =
                node.getAttribute('href');

            style.underline = true;
        }

        if (inlineStyle.fontWeight) {
            const fontWeight =
                inlineStyle.fontWeight.toLowerCase();

            style.bold =
                fontWeight === 'bold' ||
                fontWeight === 'bolder' ||
                Number.parseInt(fontWeight, 10) >= 600;
        }

        if (inlineStyle.fontStyle) {
            style.italic =
                inlineStyle.fontStyle
                    .toLowerCase()
                    .includes('italic');
        }

        if (inlineStyle.textDecoration) {
            const textDecoration =
                inlineStyle.textDecoration.toLowerCase();

            if (textDecoration.includes('underline')) {
                style.underline = true;
            }

            if (
                textDecoration.includes('line-through')
            ) {
                style.strike = true;
            }
        }

        if (inlineStyle.fontFamily) {
            style.fontFamily =
                this.mapPdfFontFamily(
                    inlineStyle.fontFamily
                );
        }

        if (inlineStyle.fontSize) {
            style.fontSize =
                this.convertCssFontSizeToPoints(
                    inlineStyle.fontSize,
                    style.fontSize
                );
        }

        if (inlineStyle.textAlign) {
            style.alignment =
                this.normalizePdfAlignment(
                    inlineStyle.textAlign
                );
        }

        if (
            node.classList.contains(
                'ql-align-center'
            )
        ) {
            style.alignment = 'center';
        } else if (
            node.classList.contains(
                'ql-align-right'
            )
        ) {
            style.alignment = 'right';
        } else if (
            node.classList.contains(
                'ql-align-justify'
            )
        ) {
            style.alignment = 'left';
        }

        Array.from(node.classList).forEach(
            (className) => {
                if (
                    className.startsWith(
                        'ql-indent-'
                    )
                ) {
                    const indentValue = Number.parseInt(
                        className.replace(
                            'ql-indent-',
                            ''
                        ),
                        10
                    );

                    if (
                        Number.isFinite(indentValue)
                    ) {
                        style.indentLevel =
                            indentValue;
                    }
                }

                if (className === 'ql-size-small') {
                    style.fontSize = 8;
                } else if (
                    className === 'ql-size-large'
                ) {
                    style.fontSize = 14;
                } else if (
                    className === 'ql-size-huge'
                ) {
                    style.fontSize = 20;
                }
            }
        );

        const leftSpacing =
            inlineStyle.paddingLeft ||
            inlineStyle.marginLeft;

        if (leftSpacing) {
            const spacingValue =
                Number.parseFloat(leftSpacing);

            if (Number.isFinite(spacingValue)) {
                style.indentLevel = Math.max(
                    style.indentLevel,
                    Math.round(spacingValue / 24)
                );
            }
        }

        if (
            tagName === 'h1' &&
            !inlineStyle.fontSize
        ) {
            style.fontSize = 15;
            style.bold = true;
        } else if (
            (tagName === 'h2' ||
                tagName === 'h3') &&
            !inlineStyle.fontSize
        ) {
            style.fontSize = 12;
            style.bold = true;
        }

        return style;
    }

    convertCssColorToPdfRgb(
        colorValue,
        fallbackColor
    ) {
        const color = String(
            colorValue || ''
        ).trim();

        const hexMatch = color.match(
            /^#([0-9a-f]{6})$/i
        );

        if (hexMatch) {
            const hex = hexMatch[1];

            return [
                Number.parseInt(hex.substring(0, 2), 16),
                Number.parseInt(hex.substring(2, 4), 16),
                Number.parseInt(hex.substring(4, 6), 16)
            ];
        }

        const rgbMatch = color.match(
            /^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/i
        );

        if (rgbMatch) {
            return [
                Number.parseInt(rgbMatch[1], 10),
                Number.parseInt(rgbMatch[2], 10),
                Number.parseInt(rgbMatch[3], 10)
            ];
        }

        return fallbackColor || [34, 34, 34];
    }

    mapPdfFontFamily(fontFamilyValue) {
        const fontFamily = String(
            fontFamilyValue || ''
        ).toLowerCase();

        if (
            fontFamily.includes('serif') ||
            fontFamily.includes('times') ||
            fontFamily.includes('georgia')
        ) {
            return 'times';
        }

        if (
            fontFamily.includes('mono') ||
            fontFamily.includes('courier')
        ) {
            return 'courier';
        }

        /*
        * jsPDF contains Helvetica, Times and Courier by default.
        * Other editor fonts are mapped to Helvetica unless a custom
        * font file is explicitly embedded.
        */
        return 'helvetica';
    }

    convertCssFontSizeToPoints(
        fontSizeValue,
        defaultSize = 10.5
    ) {
        if (!fontSizeValue) {
            return defaultSize;
        }

        const normalizedValue =
            String(fontSizeValue)
                .trim()
                .toLowerCase();

        const numericValue =
            Number.parseFloat(normalizedValue);

        if (!Number.isFinite(numericValue)) {
            return defaultSize;
        }

        if (normalizedValue.endsWith('px')) {
            return Math.max(
                6,
                Math.min(30, numericValue * 0.75)
            );
        }

        if (normalizedValue.endsWith('pt')) {
            return Math.max(
                6,
                Math.min(30, numericValue)
            );
        }

        if (normalizedValue.endsWith('em')) {
            return Math.max(
                6,
                Math.min(
                    30,
                    numericValue * defaultSize
                )
            );
        }

        return Math.max(
            6,
            Math.min(30, numericValue)
        );
    }

    normalizePdfAlignment(alignmentValue) {
        const alignment = String(
            alignmentValue || ''
        ).toLowerCase();

        if (
            alignment === 'center' ||
            alignment === 'right'
        ) {
            return alignment;
        }

        return 'left';
    }

    addPdfRichTextBlock(ctx, element) {
        const blockRuns = element.runs || [];

        if (!blockRuns.length) {
            return;
        }

        const indentLevel =
            Math.max(0, element.indentLevel || 0);

        const indentWidth =
            Math.min(indentLevel * 18, 108);

        const blockX =
            ctx.marginLeft + indentWidth;

        const blockWidth =
            ctx.usableWidth - indentWidth;

        const alignment =
            element.alignment || 'left';

        const lines =
            this.buildPdfRichTextLines(
                ctx.pdf,
                blockRuns,
                blockWidth
            );

        if (!lines.length) {
            return;
        }

        let estimatedHeight = 8;

        lines.forEach((line) => {
            estimatedHeight +=
                this.getPdfRichTextLineHeight(line);
        });

        this.ensurePdfSpace(
            ctx,
            estimatedHeight + 8
        );

        if (
            element.type === 'heading' ||
            element.type === 'mainTitle'
        ) {
            ctx.y += 10;
        }

        lines.forEach((line) => {
            const lineHeight =
                this.getPdfRichTextLineHeight(line);

            const lineWidth =
                this.getPdfRichTextLineWidth(
                    ctx.pdf,
                    line
                );

            let lineX = blockX;

            if (alignment === 'center') {
                lineX =
                    blockX +
                    (blockWidth - lineWidth) / 2;
            } else if (alignment === 'right') {
                lineX =
                    blockX +
                    blockWidth -
                    lineWidth;
            }

            this.drawPdfRichTextLine(
                ctx.pdf,
                line,
                lineX,
                ctx.y
            );

            ctx.y += lineHeight;
        });

        ctx.y +=
            element.type === 'heading' ||
            element.type === 'mainTitle'
                ? 10
                : 8;
    }

    buildPdfRichTextLines(
        pdf,
        runs,
        maximumWidth
    ) {
        const lines = [];
        let currentLine = [];
        let currentWidth = 0;

        const pushCurrentLine = () => {
            if (currentLine.length) {
                lines.push(currentLine);
            }

            currentLine = [];
            currentWidth = 0;
        };

        runs.forEach((run) => {
            const textParts = String(run.text || '')
                .split(/(\n|\s+)/);

            textParts.forEach((textPart) => {
                if (!textPart) {
                    return;
                }

                if (textPart === '\n') {
                    pushCurrentLine();
                    return;
                }

                const normalizedPart =
                    textPart.replace(/\s+/g, ' ');

                this.applyPdfRunFont(pdf, run);

                const partWidth =
                    pdf.getTextWidth(normalizedPart);

                if (
                    currentLine.length &&
                    currentWidth + partWidth >
                        maximumWidth
                ) {
                    pushCurrentLine();
                }

                if (
                    !currentLine.length &&
                    normalizedPart === ' '
                ) {
                    return;
                }

                currentLine.push({
                    ...run,
                    text: normalizedPart,
                    width: partWidth
                });

                currentWidth += partWidth;
            });
        });

        pushCurrentLine();

        return lines;
    }

    applyPdfRunFont(pdf, run) {
        const fontFamily =
            run.fontFamily || 'helvetica';

        let fontStyle = 'normal';

        if (run.bold && run.italic) {
            fontStyle = 'bolditalic';
        } else if (run.bold) {
            fontStyle = 'bold';
        } else if (run.italic) {
            fontStyle = 'italic';
        }

        pdf.setFont(fontFamily, fontStyle);
        pdf.setFontSize(run.fontSize || 10.5);
    }

    getPdfRichTextLineWidth(pdf, line) {
        return line.reduce((totalWidth, run) => {
            this.applyPdfRunFont(pdf, run);

            return (
                totalWidth +
                pdf.getTextWidth(run.text || '')
            );
        }, 0);
    }

    getPdfRichTextLineHeight(line) {
        const maximumFontSize = line.reduce(
            (currentMaximum, run) =>
                Math.max(
                    currentMaximum,
                    run.fontSize || 10.5
                ),
            10.5
        );

        return Math.max(
            14,
            maximumFontSize * 1.35
        );
    }

    drawPdfRichTextLine(
        pdf,
        line,
        startingX,
        baselineY
    ) {
        let currentX = startingX;

        line.forEach((run) => {
            const runText = run.text || '';

            if (!runText) {
                return;
            }

            this.applyPdfRunFont(pdf, run);

            pdf.setTextColor(
                ...(run.color || [34, 34, 34])
            );

            const runWidth =
                pdf.getTextWidth(runText);

            if (
                run.link &&
                typeof pdf.textWithLink === 'function'
            ) {
                pdf.textWithLink(
                    runText,
                    currentX,
                    baselineY,
                    {
                        url: run.link
                    }
                );
            } else {
                pdf.text(
                    runText,
                    currentX,
                    baselineY
                );
            }

            const fontSize =
                run.fontSize || 10.5;

            if (run.underline) {
                pdf.setLineWidth(0.5);

                pdf.line(
                    currentX,
                    baselineY + 1.5,
                    currentX + runWidth,
                    baselineY + 1.5
                );
            }

            if (run.strike) {
                pdf.setLineWidth(0.5);

                pdf.line(
                    currentX,
                    baselineY - fontSize * 0.3,
                    currentX + runWidth,
                    baselineY - fontSize * 0.3
                );
            }

            currentX += runWidth;
        });
    }
}