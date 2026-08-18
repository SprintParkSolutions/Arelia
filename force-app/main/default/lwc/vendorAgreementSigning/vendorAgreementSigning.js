import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';

import JSPDF from '@salesforce/resourceUrl/jspdfs';
import ARELIA_LOGO from '@salesforce/resourceUrl/AreliaLogo';

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
    logoBase64 = '';
    logoAspectRatio = 1;

    errorMessage = '';
    showCompletedScreen = false;
    showErrorScreen = false;

    // async connectedCallback() {
    //     try {
    //         const pageUrl = new URL(window.location.href);

    //         this.agreementId =
    //             pageUrl.searchParams.get('agreementId');

    //         await Promise.all([
    //             this.loadPdfLibrary(),
    //             this.preloadLogo()
    //         ]);

    //         await this.loadAgreement();
    //     } catch (error) {
    //         this.errorMessage = this.getErrorMessage(error);
    //     } finally {
    //         this.isLoading = false;
    //     }
    // }

    async connectedCallback() {
        try {
            const pageUrl = new URL(
                window.location.href
            );

            this.agreementId =
                pageUrl.searchParams.get(
                    'agreementId'
                );

            await Promise.all([
                this.loadPdfLibrary(),
                this.preloadLogo()
            ]);

            await this.loadAgreement();
        } catch (error) {
            this.handlePageError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async preloadLogo() {
        if (this.logoBase64) {
            return;
        }

        const logoResult =
            await this.loadOptimizedLogo(
                ARELIA_LOGO
            );

        this.logoBase64 = logoResult.base64;
        this.logoAspectRatio = logoResult.aspectRatio;
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
    //     this.showSuccessScreen = false;
    //     this.agreementLoaded = true;
    // }

    async loadAgreement() {
        if (!this.agreementId) {
            throw new Error(
                'Agreement Id is missing.'
            );
        }

        const response = await getAgreementById({
            agreementId: this.agreementId
        });

        this.agreementHtml =
            response.agreementHtml;

        this.vendorName =
            response.vendorName;

        this.errorMessage = '';
        this.showCompletedScreen = false;
        this.showErrorScreen = false;
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

            /*
            * Wait until the browser has rendered the loading overlay
            * before starting synchronous PDF generation.
            */
            await this.waitForNextPaint();

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

    waitForNextPaint() {
        return new Promise((resolve) => {
            window.requestAnimationFrame(() => {
                window.requestAnimationFrame(resolve);
            });
        });
    }

    generateSignedPdfBase64(signatureBase64) {
        const JsPdfConstructor = this.getJsPdfConstructor();

        if (!JsPdfConstructor) {
            throw new Error('jsPDF library is unavailable.');
        }

        const pdf = new JsPdfConstructor(
            'p',
            'pt',
            'a4',
            true
        );

        const ctx = {
            pdf,
            pageWidth: pdf.internal.pageSize.getWidth(),
            pageHeight: pdf.internal.pageSize.getHeight(),
            marginLeft: 46,
            marginRight: 46,
            marginTop: 40,
            marginBottom: 50,
            y: 40,
            logoBase64: this.logoBase64,
            logoAspectRatio: this.logoAspectRatio
        };

        ctx.usableWidth =
            ctx.pageWidth - ctx.marginLeft - ctx.marginRight;

        this.addSignedPdfHeader(ctx);

        this.renderAgreementHtmlToSignedPdf(
            ctx,
            this.agreementHtml
        );

        this.addVendorSignatureToPdf(
            ctx,
            signatureBase64
        );

        return pdf.output('datauristring');
    }

    addSignedPdfHeader(ctx) {
        const pdf = ctx.pdf;
        const logoWidth = 105;
        const logoHeight =
            logoWidth * ctx.logoAspectRatio;
        const logoX =
            (ctx.pageWidth - logoWidth) / 2;

        if (ctx.logoBase64) {
            pdf.addImage(
                ctx.logoBase64,
                'PNG',
                logoX,
                ctx.y,
                logoWidth,
                logoHeight,
                undefined,
                'FAST'
            );
        }

        ctx.y += logoHeight + 20;

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(17);
        pdf.setTextColor(17, 24, 39);

        pdf.text(
            'SIGNED VENDOR AGREEMENT',
            ctx.pageWidth / 2,
            ctx.y,
            {
                align: 'center'
            }
        );

        ctx.y += 27;

        pdf.setFont('helvetica', 'normal');
        pdf.setFontSize(10);
        pdf.setTextColor(90, 100, 115);

        pdf.text(
            'Interior Design Vendor / Contractor Agreement',
            ctx.pageWidth / 2,
            ctx.y,
            {
                align: 'center'
            }
        );

        ctx.y += 25;

        pdf.setDrawColor(31, 78, 121);
        pdf.setLineWidth(1.4);

        pdf.line(
            ctx.marginLeft,
            ctx.y,
            ctx.pageWidth - ctx.marginRight,
            ctx.y
        );

        ctx.y += 28;
    }

    renderAgreementHtmlToSignedPdf(ctx, html) {
        const container = document.createElement('div');

        container.innerHTML = html || '';

        container
            .querySelectorAll(
                'script, style, iframe, object, embed, img'
            )
            .forEach((node) => node.remove());

        this.renderSignedPdfContentInOrder(
            ctx,
            container
        );
    }

    renderSignedPdfContentInOrder(ctx, container) {
        Array.from(container.children).forEach((node) => {
            this.renderSignedPdfNode(ctx, node);
        });
    }

    renderSignedPdfNode(ctx, node) {
        if (!node || node.nodeType !== Node.ELEMENT_NODE) {
            return;
        }

        const tag = node.tagName.toLowerCase();

        if (tag === 'div') {
            const className =
                String(node.className || '');

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

        const text = this.cleanPdfText(
            node.textContent
        );

        if (!text) {
            return;
        }

        if (text.toUpperCase() === 'ARELIA SPACE') {
            return;
        }

        if (text.toUpperCase() === 'VENDOR AGREEMENT') {
            return;
        }

        if (
            text.toLowerCase().includes(
                'interior design vendor'
            )
        ) {
            return;
        }

        if (
            tag === 'h1'
            || tag === 'h2'
            || tag === 'h3'
        ) {
            this.addSignedPdfSectionHeading(
                ctx,
                text
            );

            return;
        }

        if (tag === 'p') {
            this.addSignedPdfRichBlock(ctx, node);
            return;
        }

        if (tag === 'ul' || tag === 'ol') {
            this.addSignedPdfRichList(
                ctx,
                node,
                tag === 'ol'
            );

            return;
        }

        if (tag === 'li') {
            this.addSignedPdfRichListItem(
                ctx,
                node,
                '•',
                0
            );

            return;
        }

        this.addSignedPdfRichBlock(ctx, node);
    }

    addSignedPdfSectionHeading(ctx, text) {
        const pdf = ctx.pdf;

        this.ensureSignedPdfSpace(ctx, 34);

        ctx.y += 8;

        pdf.setFillColor(31, 78, 121);
        pdf.rect(
            ctx.marginLeft,
            ctx.y - 13,
            4,
            18,
            'F'
        );

        pdf.setFont('helvetica', 'bold');
        pdf.setFontSize(12);
        pdf.setTextColor(31, 78, 121);

        const lines = pdf.splitTextToSize(
            text,
            ctx.usableWidth - 14
        );

        lines.forEach((line) => {
            pdf.text(
                line,
                ctx.marginLeft + 12,
                ctx.y
            );

            ctx.y += 15;
        });

        ctx.y += 7;
    }

    addSignedPdfRichBlock(ctx, node) {
        const segments =
            this.collectRichTextSegments(
                node,
                this.createDefaultTextStyle()
            );

        if (!segments.length) {
            return;
        }

        const alignment =
            this.getNodeAlignment(node);

        const indent =
            this.getNodeIndent(node);

        const availableWidth =
            ctx.usableWidth - indent;

        this.renderRichTextSegments(
            ctx,
            segments,
            {
                x: ctx.marginLeft + indent,
                width: availableWidth,
                alignment,
                fontSize: 10,
                lineHeight: 13,
                spacingAfter: 7
            }
        );
    }

    addSignedPdfRichList(ctx, listNode, ordered) {
        const directItems =
            Array.from(listNode.children)
                .filter(
                    (child) =>
                        child.tagName.toLowerCase()
                        === 'li'
                );

        directItems.forEach((item, index) => {
            const marker = ordered
                ? `${index + 1}.`
                : '•';

            this.addSignedPdfRichListItem(
                ctx,
                item,
                marker,
                0
            );
        });
    }

    addSignedPdfRichListItem(
        ctx,
        itemNode,
        marker,
        nestingLevel
    ) {
        const baseIndent =
            14 + (nestingLevel * 16);

        const markerWidth = 18;

        const alignment =
            this.getNodeAlignment(itemNode);

        const contentSegments = [];

        Array.from(itemNode.childNodes)
            .forEach((child) => {
                if (
                    child.nodeType
                        === Node.ELEMENT_NODE
                    && ['ul', 'ol'].includes(
                        child.tagName.toLowerCase()
                    )
                ) {
                    return;
                }

                contentSegments.push(
                    ...this.collectRichTextSegments(
                        child,
                        this.createDefaultTextStyle()
                    )
                );
            });

        if (contentSegments.length) {
            this.ensureSignedPdfSpace(ctx, 18);

            ctx.pdf.setFont(
                'helvetica',
                'normal'
            );

            ctx.pdf.setFontSize(10);
            ctx.pdf.setTextColor(31, 41, 55);

            ctx.pdf.text(
                marker,
                ctx.marginLeft
                    + baseIndent
                    - markerWidth,
                ctx.y
            );

            this.renderRichTextSegments(
                ctx,
                contentSegments,
                {
                    x:
                        ctx.marginLeft
                        + baseIndent,
                    width:
                        ctx.usableWidth
                        - baseIndent,
                    alignment,
                    fontSize: 10,
                    lineHeight: 13,
                    spacingAfter: 4
                }
            );
        }

        Array.from(itemNode.children)
            .forEach((child) => {
                const childTag =
                    child.tagName.toLowerCase();

                if (
                    childTag !== 'ul'
                    && childTag !== 'ol'
                ) {
                    return;
                }

                const childOrdered =
                    childTag === 'ol';

                const childItems =
                    Array.from(child.children)
                        .filter(
                            (element) =>
                                element.tagName
                                    .toLowerCase()
                                === 'li'
                        );

                childItems.forEach(
                    (childItem, index) => {
                        this.addSignedPdfRichListItem(
                            ctx,
                            childItem,
                            childOrdered
                                ? `${index + 1}.`
                                : '•',
                            nestingLevel + 1
                        );
                    }
                );
            });
    }

    renderRichTextSegments(
        ctx,
        segments,
        options
    ) {
        const pdf = ctx.pdf;

        const fontSize =
            options.fontSize || 10;

        const lineHeight =
            options.lineHeight || 13;

        const lines =
            this.buildRichTextLines(
                pdf,
                segments,
                options.width,
                fontSize
            );

        lines.forEach((line) => {
            this.ensureSignedPdfSpace(
                ctx,
                lineHeight + 2
            );

            const lineWidth = line.reduce(
                (total, token) =>
                    total + token.width,
                0
            );

            let startX = options.x;

            if (options.alignment === 'center') {
                startX +=
                    (options.width - lineWidth) / 2;
            } else if (
                options.alignment === 'right'
            ) {
                startX +=
                    options.width - lineWidth;
            }

            let currentX = startX;

            line.forEach((token) => {
                this.applyPdfTextStyle(
                    pdf,
                    token.style,
                    fontSize
                );

                pdf.text(
                    token.text,
                    currentX,
                    ctx.y
                );

                this.drawPdfTextDecorations(
                    pdf,
                    token,
                    currentX,
                    ctx.y,
                    fontSize
                );

                currentX += token.width;
            });

            ctx.y += lineHeight;
        });

        ctx.y += options.spacingAfter || 0;
    }

    buildRichTextLines(
        pdf,
        segments,
        maximumWidth,
        fontSize
    ) {
        const lines = [];
        let currentLine = [];
        let currentWidth = 0;

        segments.forEach((segment) => {
            if (segment.lineBreak) {
                lines.push(currentLine);
                currentLine = [];
                currentWidth = 0;
                return;
            }

            const tokens =
                this.splitRichTextSegment(segment);

            tokens.forEach((token) => {
                this.applyPdfTextStyle(
                    pdf,
                    token.style,
                    fontSize
                );

                let tokenText = token.text;

                let tokenWidth =
                    pdf.getTextWidth(tokenText);

                if (
                    currentLine.length
                    && currentWidth + tokenWidth
                        > maximumWidth
                ) {
                    lines.push(currentLine);

                    currentLine = [];
                    currentWidth = 0;

                    tokenText =
                        tokenText.replace(
                            /^\s+/,
                            ''
                        );

                    if (!tokenText) {
                        return;
                    }

                    this.applyPdfTextStyle(
                        pdf,
                        token.style,
                        fontSize
                    );

                    tokenWidth =
                        pdf.getTextWidth(tokenText);
                }

                currentLine.push({
                    text: tokenText,
                    style: token.style,
                    width: tokenWidth
                });

                currentWidth += tokenWidth;
            });
        });

        if (currentLine.length) {
            lines.push(currentLine);
        }

        return lines;
    }

    splitRichTextSegment(segment) {
        return segment.text
            .replace(/\u00a0/g, ' ')
            .split(/(\s+)/)
            .filter((value) => value !== '')
            .map((value) => ({
                text: value,
                style: segment.style
            }));
    }

    collectRichTextSegments(
        node,
        inheritedStyle
    ) {
        if (!node) {
            return [];
        }

        if (node.nodeType === Node.TEXT_NODE) {
            const value =
                String(node.textContent || '')
                    .replace(/\u00a0/g, ' ');

            return value
                ? [{
                    text: value,
                    style: {
                        ...inheritedStyle
                    }
                }]
                : [];
        }

        if (
            node.nodeType
                !== Node.ELEMENT_NODE
        ) {
            return [];
        }

        const tag =
            node.tagName.toLowerCase();

        if (tag === 'br') {
            return [{
                lineBreak: true
            }];
        }

        const style =
            this.mergeRichTextStyle(
                inheritedStyle,
                node
            );

        const segments = [];

        Array.from(node.childNodes)
            .forEach((child) => {
                segments.push(
                    ...this.collectRichTextSegments(
                        child,
                        style
                    )
                );
            });

        return segments;
    }

    createDefaultTextStyle() {
        return {
            bold: false,
            italic: false,
            underline: false,
            strike: false,
            color: [31, 41, 55]
        };
    }

    mergeRichTextStyle(
        inheritedStyle,
        node
    ) {
        const style = {
            ...inheritedStyle
        };

        const tag =
            node.tagName.toLowerCase();

        const inlineStyle = node.style;

        if (
            tag === 'strong'
            || tag === 'b'
        ) {
            style.bold = true;
        }

        if (
            tag === 'em'
            || tag === 'i'
        ) {
            style.italic = true;
        }

        if (tag === 'u') {
            style.underline = true;
        }

        if (
            tag === 's'
            || tag === 'strike'
            || tag === 'del'
        ) {
            style.strike = true;
        }

        const fontWeight =
            inlineStyle.fontWeight;

        if (
            fontWeight === 'bold'
            || Number.parseInt(
                fontWeight,
                10
            ) >= 600
        ) {
            style.bold = true;
        }

        if (
            inlineStyle.fontStyle
                === 'italic'
        ) {
            style.italic = true;
        }

        const decoration = (
            inlineStyle.textDecoration
            || inlineStyle.textDecorationLine
            || ''
        ).toLowerCase();

        if (
            decoration.includes('underline')
        ) {
            style.underline = true;
        }

        if (
            decoration.includes('line-through')
        ) {
            style.strike = true;
        }

        if (inlineStyle.color) {
            style.color =
                this.parseCssColor(
                    inlineStyle.color,
                    style.color
                );
        }

        return style;
    }

    applyPdfTextStyle(
        pdf,
        style,
        fontSize
    ) {
        let fontStyle = 'normal';

        if (style.bold && style.italic) {
            fontStyle = 'bolditalic';
        } else if (style.bold) {
            fontStyle = 'bold';
        } else if (style.italic) {
            fontStyle = 'italic';
        }

        pdf.setFont(
            'helvetica',
            fontStyle
        );

        pdf.setFontSize(fontSize);

        const color =
            style.color || [31, 41, 55];

        pdf.setTextColor(
            color[0],
            color[1],
            color[2]
        );
    }

    drawPdfTextDecorations(
        pdf,
        token,
        x,
        baselineY,
        fontSize
    ) {
        const color =
            token.style.color
            || [31, 41, 55];

        pdf.setDrawColor(
            color[0],
            color[1],
            color[2]
        );

        pdf.setLineWidth(0.5);

        if (token.style.underline) {
            pdf.line(
                x,
                baselineY + 1.5,
                x + token.width,
                baselineY + 1.5
            );
        }

        if (token.style.strike) {
            pdf.line(
                x,
                baselineY
                    - (fontSize * 0.3),
                x + token.width,
                baselineY
                    - (fontSize * 0.3)
            );
        }
    }

    getNodeAlignment(node) {
        const className =
            String(node.className || '');

        const alignment =
            node.style?.textAlign;

        if (
            alignment === 'center'
            || className.includes(
                'ql-align-center'
            )
        ) {
            return 'center';
        }

        if (
            alignment === 'right'
            || className.includes(
                'ql-align-right'
            )
        ) {
            return 'right';
        }

        return 'left';
    }

    getNodeIndent(node) {
        const className =
            String(node.className || '');

        const indentMatch =
            className.match(
                /ql-indent-(\d+)/
            );

        if (indentMatch) {
            return Number(
                indentMatch[1]
            ) * 18;
        }

        const marginLeft =
            Number.parseFloat(
                node.style?.marginLeft
                    || '0'
            );

        return Number.isFinite(marginLeft)
            ? Math.min(marginLeft, 120)
            : 0;
    }

    parseCssColor(value, fallback) {
        if (!value) {
            return fallback;
        }

        const normalized =
            value.trim().toLowerCase();

        if (normalized.startsWith('#')) {
            const hexadecimal =
                normalized.substring(1);

            if (hexadecimal.length === 3) {
                return hexadecimal
                    .split('')
                    .map(
                        (character) =>
                            Number.parseInt(
                                character
                                    + character,
                                16
                            )
                    );
            }

            if (hexadecimal.length >= 6) {
                return [
                    Number.parseInt(
                        hexadecimal.substring(
                            0,
                            2
                        ),
                        16
                    ),
                    Number.parseInt(
                        hexadecimal.substring(
                            2,
                            4
                        ),
                        16
                    ),
                    Number.parseInt(
                        hexadecimal.substring(
                            4,
                            6
                        ),
                        16
                    )
                ];
            }
        }

        const rgbMatch =
            normalized.match(
                /rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/
            );

        if (rgbMatch) {
            return [
                Number(rgbMatch[1]),
                Number(rgbMatch[2]),
                Number(rgbMatch[3])
            ];
        }

        const namedColors = {
            black: [0, 0, 0],
            blue: [0, 0, 255],
            gray: [128, 128, 128],
            green: [0, 128, 0],
            orange: [255, 165, 0],
            purple: [128, 0, 128],
            red: [255, 0, 0],
            white: [255, 255, 255],
            yellow: [255, 255, 0]
        };

        return namedColors[normalized]
            || fallback;
    }

    renderSingleAgreementTable(ctx, table) {
        const rows = [];

        table.querySelectorAll('tr')
            .forEach((tr) => {
                const cells =
                    Array.from(
                        tr.querySelectorAll(
                            'td, th'
                        )
                    ).map(
                        (cell) =>
                            this.cleanPdfText(
                                cell.textContent
                            )
                    );

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

        const valueWidth =
            ctx.usableWidth - labelWidth;

        const rowHeight = 30;

        rows.forEach((row) => {
            this.ensureSignedPdfSpace(
                ctx,
                rowHeight + 4
            );

            pdf.setDrawColor(
                197,
                208,
                222
            );

            pdf.setLineWidth(0.7);

            pdf.setFillColor(
                232,
                240,
                248
            );

            pdf.rect(
                ctx.marginLeft,
                ctx.y,
                labelWidth,
                rowHeight,
                'FD'
            );

            pdf.setFillColor(
                255,
                255,
                255
            );

            pdf.rect(
                ctx.marginLeft
                    + labelWidth,
                ctx.y,
                valueWidth,
                rowHeight,
                'FD'
            );

            pdf.setFont(
                'helvetica',
                'bold'
            );

            pdf.setFontSize(9.5);
            pdf.setTextColor(22, 71, 116);

            pdf.text(
                row.label,
                ctx.marginLeft + 8,
                ctx.y + 19
            );

            pdf.setFont(
                'helvetica',
                'normal'
            );

            pdf.setFontSize(9.5);
            pdf.setTextColor(31, 41, 55);

            const valueLines =
                pdf.splitTextToSize(
                    row.value || '',
                    valueWidth - 14
                );

            pdf.text(
                valueLines,
                ctx.marginLeft
                    + labelWidth
                    + 8,
                ctx.y + 19
            );

            ctx.y += rowHeight;
        });

        ctx.y += 20;
    }

    addVendorSignatureToPdf(
        ctx,
        signatureBase64
    ) {
        const pdf = ctx.pdf;

        this.ensureSignedPdfSpace(ctx, 170);

        ctx.y += 16;

        pdf.setDrawColor(31, 78, 121);
        pdf.setLineWidth(1);

        pdf.line(
            ctx.marginLeft,
            ctx.y,
            ctx.pageWidth - ctx.marginRight,
            ctx.y
        );

        ctx.y += 28;

        pdf.setFont(
            'helvetica',
            'bold'
        );

        pdf.setFontSize(13);
        pdf.setTextColor(31, 78, 121);

        pdf.text(
            'VENDOR DIGITAL SIGNATURE',
            ctx.marginLeft,
            ctx.y
        );

        ctx.y += 20;

        pdf.setFont(
            'helvetica',
            'normal'
        );

        pdf.setFontSize(10);
        pdf.setTextColor(31, 41, 55);

        pdf.text(
            `Vendor: ${this.vendorName || ''}`,
            ctx.marginLeft,
            ctx.y
        );

        ctx.y += 16;

        pdf.text(
            `Signed Date: ${new Date().toLocaleString()}`,
            ctx.marginLeft,
            ctx.y
        );

        ctx.y += 18;

        pdf.setDrawColor(200, 200, 200);

        pdf.rect(
            ctx.marginLeft,
            ctx.y,
            250,
            92
        );

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

    ensureSignedPdfSpace(
        ctx,
        requiredHeight
    ) {
        if (
            ctx.y + requiredHeight
            <= ctx.pageHeight
                - ctx.marginBottom
        ) {
            return;
        }

        ctx.pdf.addPage();

        /*
        * This method adds the same logo used on page 1
        * and sets ctx.y below the repeated page header.
        */
        this.addSignedPdfPageHeader(ctx);
    }

    addSignedPdfPageHeader(ctx) {
        const pdf = ctx.pdf;

        /*
        * Keep the logo dimensions identical to page 1.
        */
        const logoWidth = 105;

        const logoHeight =
            logoWidth * ctx.logoAspectRatio;

        const logoX =
            (ctx.pageWidth - logoWidth) / 2;

        const logoY = 18;

        if (ctx.logoBase64) {
            pdf.addImage(
                ctx.logoBase64,
                'PNG',
                logoX,
                logoY,
                logoWidth,
                logoHeight,
                undefined,
                'FAST'
            );
        }

        /*
        * Retain the existing subsequent-page header text.
        */
        const headerTextY =
            logoY + logoHeight + 14;

        pdf.setFont(
            'helvetica',
            'bold'
        );

        pdf.setFontSize(9);
        pdf.setTextColor(90, 100, 115);

        pdf.text(
            'ARELIA SPACE - SIGNED VENDOR AGREEMENT',
            ctx.pageWidth / 2,
            headerTextY,
            {
                align: 'center'
            }
        );

        const dividerY =
            headerTextY + 10;

        pdf.setDrawColor(220, 220, 220);
        pdf.setLineWidth(0.7);

        pdf.line(
            ctx.marginLeft,
            dividerY,
            ctx.pageWidth - ctx.marginRight,
            dividerY
        );

        /*
        * Start page content below the repeated logo,
        * header text, and divider line.
        */
        ctx.y = dividerY + 24;
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
        const container =
            document.createElement('div');

        container.innerHTML =
            htmlValue || '';

        return (
            container.textContent || ''
        )
            .replace(/\s+/g, ' ')
            .trim();
    }

    getJsPdfConstructor() {
        if (
            window.jspdf
            && window.jspdf.jsPDF
        ) {
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

    handleRedirect() {
        if (!REDIRECT_URL) {
            this.showToast(
                'Redirect URL Missing',
                'Redirect URL is not configured.',
                'error'
            );

            return;
        }

        window.location.assign(
            REDIRECT_URL
        );
    }

    loadOptimizedLogo(imageUrl) {
        return new Promise(
            (resolve, reject) => {
                const image = new Image();

                image.onload = () => {
                    try {
                        const maximumWidth = 300;

                        const originalWidth =
                            image.naturalWidth
                            || image.width;

                        const originalHeight =
                            image.naturalHeight
                            || image.height;

                        if (
                            !originalWidth
                            || !originalHeight
                        ) {
                            reject(
                                new Error(
                                    'Logo dimensions could not be determined.'
                                )
                            );

                            return;
                        }

                        const scaleRatio =
                            originalWidth
                                > maximumWidth
                                ? maximumWidth
                                    / originalWidth
                                : 1;

                        const resizedWidth =
                            Math.round(
                                originalWidth
                                    * scaleRatio
                            );

                        const resizedHeight =
                            Math.round(
                                originalHeight
                                    * scaleRatio
                            );

                        const canvas =
                            document.createElement(
                                'canvas'
                            );

                        canvas.width =
                            resizedWidth;

                        canvas.height =
                            resizedHeight;

                        const context =
                            canvas.getContext('2d');

                        if (!context) {
                            reject(
                                new Error(
                                    'Logo image could not be processed.'
                                )
                            );

                            return;
                        }

                        context.drawImage(
                            image,
                            0,
                            0,
                            resizedWidth,
                            resizedHeight
                        );

                        resolve({
                            base64:
                                canvas.toDataURL(
                                    'image/png'
                                ),
                            aspectRatio:
                                originalHeight
                                    / originalWidth
                        });
                    } catch (error) {
                        reject(
                            new Error(
                                'Logo image could not be added to the PDF.'
                            )
                        );
                    }
                };

                image.onerror = () => {
                    reject(
                        new Error(
                            'Arelia logo could not be loaded.'
                        )
                    );
                };

                image.src = imageUrl;
            }
        );
    }

    handlePageError(error) {
        const message =
            this.getErrorMessage(error);

        const normalizedMessage =
            message.toLowerCase();

        const isAlreadySigned =
            normalizedMessage.includes(
                'already been signed'
            );

        const isAlreadySubmitted =
            normalizedMessage.includes(
                'signature has already been submitted'
            );

        this.agreementLoaded = false;
        this.showSuccessScreen = false;

        if (
            isAlreadySigned
            || isAlreadySubmitted
        ) {
            this.showCompletedScreen = true;
            this.showErrorScreen = false;
            this.errorMessage = '';

            return;
        }

        this.showCompletedScreen = false;
        this.showErrorScreen = true;
        this.errorMessage = message;
    }

    handleRetry() {
        window.location.reload();
    }
}