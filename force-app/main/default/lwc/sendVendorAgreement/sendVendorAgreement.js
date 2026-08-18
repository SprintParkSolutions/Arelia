import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getAgreement
    from '@salesforce/apex/VendorAgreementService.getAgreement';

import saveAgreement
    from '@salesforce/apex/VendorAgreementService.saveAgreement';

import sendAgreement
    from '@salesforce/apex/VendorAgreementService.sendAgreement';

export default class SendVendorAgreement extends LightningElement {
    _recordId;
    hasLoadedAgreement = false;

    agreementHtml = '';
    vendorName = '';
    vendorEmail = '';
    isLoading = true;
    isEditing = false;

    formats = [
        'bold',
        'italic',
        'underline',
        'strike',
        'list',
        'indent',
        'align',
        'link',
        'table',
        'header',
        'color',
        'background'
    ];

    @api
    set recordId(value) {
        this._recordId = value;

        if (
            value
            && !this.hasLoadedAgreement
        ) {
            this.hasLoadedAgreement = true;
            this.loadAgreement();
        }
    }

    get recordId() {
        return this._recordId;
    }

    /**
     * Returns only the agreement body for the preview.
     *
     * The fixed header is rendered separately in the HTML
     * template so it remains identical before and after
     * rich-text editing.
     */
    get previewAgreementBodyHtml() {
        return this.removeAgreementHeaderForPreview(
            this.agreementHtml
        );
    }

    async loadAgreement() {
        this.isLoading = true;

        try {
            if (!this.recordId) {
                throw new Error(
                    'Vendor Opportunity record Id was not received.'
                );
            }

            const response = await getAgreement({
                vendorOpportunityId: this.recordId
            });

            this.agreementHtml =
                response.agreementHtml;

            this.vendorName =
                response.vendorName;

            this.vendorEmail =
                response.vendorEmail;
        } catch (error) {
            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );

            this.closeAction();
        } finally {
            this.isLoading = false;
        }
    }

    handleAgreementChange(event) {
        this.agreementHtml =
            event.target.value;
    }

    handleEdit() {
        this.isEditing = true;
    }

    async handleSave() {
        this.isLoading = true;

        try {
            const normalizedAgreementHtml =
                this.normalizeAgreementHtml(
                    this.agreementHtml
                );

            const response = await saveAgreement({
                vendorOpportunityId:
                    this.recordId,
                agreementHtml:
                    normalizedAgreementHtml
            });

            this.agreementHtml =
                response.agreementHtml;

            this.isEditing = false;

            this.showToast(
                'Success',
                'Vendor Agreement has been saved.',
                'success'
            );
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

    async handleSend() {
        this.isLoading = true;

        try {
            if (this.isEditing) {
                const normalizedAgreementHtml =
                    this.normalizeAgreementHtml(
                        this.agreementHtml
                    );

                const response =
                    await saveAgreement({
                        vendorOpportunityId:
                            this.recordId,
                        agreementHtml:
                            normalizedAgreementHtml
                    });

                this.agreementHtml =
                    response.agreementHtml;

                this.isEditing = false;
            }

            await sendAgreement({
                vendorOpportunityId:
                    this.recordId
            });

            this.showToast(
                'Success',
                'Vendor Agreement has been sent successfully.',
                'success'
            );

            this.closeAction();
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

    /**
     * Removes the stored agreement header only from the
     * preview copy of the HTML.
     *
     * Agreement_HTML__c itself is not changed by this
     * method.
     */
    removeAgreementHeaderForPreview(
        htmlValue
    ) {
        if (!htmlValue) {
            return '';
        }

        const container =
            document.createElement('div');

        container.innerHTML =
            htmlValue;

        const classBasedHeader =
            container.querySelector(
                '.agreement-header'
            );

        if (classBasedHeader) {
            classBasedHeader.remove();

            return container.innerHTML;
        }

        /*
         * Fallback for HTML rewritten by
         * lightning-input-rich-text where the original
         * agreement-header class may no longer exist.
         */
        const companyElement =
            this.findLeafElementByText(
                container,
                'ARELIA SPACE'
            );

        const titleElement =
            this.findLeafElementByText(
                container,
                'VENDOR AGREEMENT'
            );

        const subtitleElement =
            this.findLeafElementByText(
                container,
                'Interior Design Vendor / Contractor Agreement'
            );

        [
            companyElement,
            titleElement,
            subtitleElement
        ].forEach((element) => {
            this.removeElementAndEmptyParent(
                element,
                container
            );
        });

        return container.innerHTML;
    }

    /**
     * Removes an agreement-header element from the
     * preview copy and removes its wrapper when the
     * wrapper becomes empty.
     */
    removeElementAndEmptyParent(
        element,
        rootContainer
    ) {
        if (!element) {
            return;
        }

        const parent =
            element.parentElement;

        element.remove();

        if (
            parent
            && parent !== rootContainer
            && !this.cleanText(
                parent.textContent
            )
            && !parent.querySelector(
                'table, ul, ol, img, a'
            )
        ) {
            parent.remove();
        }
    }

    /**
     * Restores the structural classes required by the
     * Visualforce PDF after rich-text editing.
     */
    normalizeAgreementHtml(htmlValue) {
        if (!htmlValue) {
            return '';
        }

        const container =
            document.createElement('div');

        container.innerHTML =
            htmlValue;

        const agreementRoot =
            this.ensureAgreementRoot(
                container
            );

        this.restoreAgreementHeader(
            agreementRoot
        );

        this.restoreAgreementTables(
            agreementRoot
        );

        this.restoreAgreementSections(
            agreementRoot
        );

        return container.innerHTML;
    }

    ensureAgreementRoot(container) {
        const existingRoot =
            container.querySelector(
                '.agreement-page'
            );

        if (existingRoot) {
            return existingRoot;
        }

        const agreementRoot =
            document.createElement('div');

        agreementRoot.className =
            'agreement-page';

        while (container.firstChild) {
            agreementRoot.appendChild(
                container.firstChild
            );
        }

        container.appendChild(
            agreementRoot
        );

        return agreementRoot;
    }

    restoreAgreementHeader(
        agreementRoot
    ) {
        let header =
            agreementRoot.querySelector(
                '.agreement-header'
            );

        const companyElement =
            this.findLeafElementByText(
                agreementRoot,
                'ARELIA SPACE'
            );

        const titleElement =
            this.findLeafElementByText(
                agreementRoot,
                'VENDOR AGREEMENT'
            );

        const subtitleElement =
            this.findLeafElementByText(
                agreementRoot,
                'Interior Design Vendor / Contractor Agreement'
            );

        if (
            !companyElement
            && !titleElement
            && !subtitleElement
        ) {
            return;
        }

        if (!header) {
            header =
                document.createElement('div');

            header.className =
                'agreement-header';

            const firstHeaderElement =
                this.getFirstElementInDocumentOrder([
                    companyElement,
                    titleElement,
                    subtitleElement
                ]);

            if (
                firstHeaderElement
                && firstHeaderElement.parentNode
            ) {
                firstHeaderElement.parentNode
                    .insertBefore(
                        header,
                        firstHeaderElement
                    );
            } else {
                agreementRoot.insertBefore(
                    header,
                    agreementRoot.firstChild
                );
            }
        }

        header.classList.add(
            'agreement-header'
        );

        header.style.textAlign =
            'center';

        header.style.width =
            '100%';

        if (companyElement) {
            companyElement.classList.add(
                'company-name'
            );

            companyElement.style.textAlign =
                'center';

            companyElement.style.width =
                '100%';

            /*
             * Do not set display:block inline.
             *
             * The unsigned Visualforce PDF must be able
             * to hide this value through .company-name.
             */
            companyElement.style.removeProperty(
                'display'
            );

            header.appendChild(
                companyElement
            );
        }

        if (titleElement) {
            titleElement.classList.add(
                'agreement-title'
            );

            titleElement.style.textAlign =
                'center';

            titleElement.style.width =
                '100%';

            titleElement.style.removeProperty(
                'display'
            );

            header.appendChild(
                titleElement
            );
        }

        if (subtitleElement) {
            subtitleElement.classList.add(
                'agreement-subtitle'
            );

            subtitleElement.style.textAlign =
                'center';

            subtitleElement.style.width =
                '100%';

            subtitleElement.style.removeProperty(
                'display'
            );

            header.appendChild(
                subtitleElement
            );
        }
    }

    restoreAgreementTables(
        agreementRoot
    ) {
        const tables =
            Array.from(
                agreementRoot.querySelectorAll(
                    'table'
                )
            );

        if (!tables.length) {
            return;
        }

        tables[0].classList.add(
            'reference-table'
        );

        if (tables.length > 1) {
            const lastTable =
                tables[
                    tables.length - 1
                ];

            lastTable.classList.add(
                'details-table'
            );
        }
    }

    restoreAgreementSections(
        agreementRoot
    ) {
        const headings =
            Array.from(
                agreementRoot.querySelectorAll(
                    'h1, h2, h3'
                )
            );

        headings.forEach((heading) => {
            const parent =
                heading.parentElement;

            if (!parent) {
                return;
            }

            if (
                parent.classList.contains(
                    'agreement-header'
                )
                || parent.classList.contains(
                    'vendor-details'
                )
                || parent.classList.contains(
                    'signature-block'
                )
                || parent.classList.contains(
                    'digital-signature'
                )
            ) {
                return;
            }

            const headingText =
                this.cleanText(
                    heading.textContent
                );

            if (
                this.isNumberedAgreementHeading(
                    headingText
                )
            ) {
                parent.classList.add(
                    'agreement-section'
                );
            }

            if (
                headingText.toLowerCase()
                === 'vendor details'
            ) {
                parent.classList.add(
                    'vendor-details'
                );
            }
        });
    }

    findLeafElementByText(
        container,
        expectedText
    ) {
        const normalizedExpected =
            this.cleanText(
                expectedText
            ).toLowerCase();

        const candidates =
            Array.from(
                container.querySelectorAll(
                    'div, p, span, h1, h2, h3'
                )
            );

        return candidates.find((element) => {
            const elementText =
                this.cleanText(
                    element.textContent
                ).toLowerCase();

            if (
                elementText
                !== normalizedExpected
            ) {
                return false;
            }

            const childHasSameText =
                Array.from(
                    element.children
                ).some((child) => {
                    return this.cleanText(
                        child.textContent
                    ).toLowerCase()
                        === normalizedExpected;
                });

            return !childHasSameText;
        });
    }

    getFirstElementInDocumentOrder(
        elements
    ) {
        const availableElements =
            elements.filter(
                (element) =>
                    Boolean(element)
            );

        if (!availableElements.length) {
            return null;
        }

        return availableElements.reduce(
            (
                firstElement,
                currentElement
            ) => {
                if (
                    firstElement
                    === currentElement
                ) {
                    return firstElement;
                }

                const position =
                    firstElement
                        .compareDocumentPosition(
                            currentElement
                        );

                if (
                    position
                    & Node
                        .DOCUMENT_POSITION_PRECEDING
                ) {
                    return currentElement;
                }

                return firstElement;
            }
        );
    }

    isNumberedAgreementHeading(
        value
    ) {
        if (!value) {
            return false;
        }

        return /^\d+\.\s+\S+/.test(
            value
        );
    }

    cleanText(value) {
        if (!value) {
            return '';
        }

        return String(value)
            .replace(/\u00a0/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    }

    handleCancel() {
        this.closeAction();
    }

    closeAction() {
        this.dispatchEvent(
            new CloseActionScreenEvent()
        );
    }

    showToast(
        title,
        message,
        variant
    ) {
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
}