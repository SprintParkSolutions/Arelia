import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAgreement from '@salesforce/apex/VendorAgreementService.getAgreement';
import saveAgreement from '@salesforce/apex/VendorAgreementService.saveAgreement';
import sendAgreement from '@salesforce/apex/VendorAgreementService.sendAgreement';
import ARELIA_LOGO from '@salesforce/resourceUrl/AreliaLogo';

export default class SendVendorAgreement extends LightningElement {
    _recordId;
    hasLoadedAgreement = false;
    agreementHtml = '';
    vendorName = '';
    vendorEmail = '';
    isLoading = true;
    isEditing = false;
    agreementHtml = '';
    editableAgreementHtml = '';
    protectedAgreementHeaderHtml = '';
    /*
    * Protected Salesforce-generated sections.
    */
    protectedProjectInformationTableHtml = '';
    protectedVendorDetailsSectionHtml = '';
    protectedVendorDetailsTableHtml = '';
    protectedProjectInformationSignature = '';
    protectedVendorDetailsSignature = '';

    /*
    * Prevent recursive rich-text onchange processing when
    * protected content is restored.
    */
    isRestoringProtectedContent = false;

    formats = ['bold', 'italic', 'underline', 'strike', 'list', 'indent', 'align', 'link', 'table', 'header', 'color', 'background'];

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

    get areliaLogoUrl() {
        return ARELIA_LOGO;
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

    renderedCallback() {
        this.renderAgreementPreview();
    }

    /**
     * Renders the Vendor Agreement HTML directly into the preview
     * container.
     *
     * This affects ONLY the modal UI.
     *
     * Agreement_HTML__c is not changed and therefore the existing
     * unsigned and signed Vendor Agreement PDFs remain unchanged.
     */
    renderAgreementPreview() {
        if (this.isEditing) {
            return;
        }

        const previewContainer =
            this.template.querySelector(
                '.modal-agreement-content'
            );

        if (!previewContainer) {
            return;
        }

        const previewHtml =
            this.previewAgreementBodyHtml || '';

        /*
        * Avoid unnecessary DOM writes every time
        * renderedCallback executes.
        */
        if (
            previewContainer.dataset.renderedHtml ===
            previewHtml
        ) {
            return;
        }

        previewContainer.innerHTML =
            previewHtml;

        previewContainer.dataset.renderedHtml =
            previewHtml;
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

            this.agreementHtml = response.agreementHtml;
            this.agreementHtml = response.agreementHtml;

            /*
            * Preserve the original agreement header.
            * This header remains part of Agreement_HTML__c because the
            * existing unsigned/signed PDF functionality depends on the
            * existing agreement structure.
            *
            * It is removed only from the LWC display/editor.
            */
            this.captureProtectedAgreementHeader(this.agreementHtml);

            /*
            * The rich-text editor receives only the editable body.
            */
            this.editableAgreementHtml = this.removeAgreementHeaderForPreview(this.agreementHtml);

            /*
            * Existing Salesforce-generated content protection.
            */
            this.captureProtectedVendorAgreementSections(this.agreementHtml);
            this.vendorName = response.vendorName;
            this.vendorEmail = response.vendorEmail;
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

    /**
     * Captures the original stored agreement header.
     *
     * The header must remain in Agreement_HTML__c because the
     * existing PDF implementations depend on the current structure.
     */
    captureProtectedAgreementHeader(html) {
        this.protectedAgreementHeaderHtml = '';

        if (!html) {
            return;
        }

        const container = document.createElement('div');
        container.innerHTML = html;

        const agreementHeader =
            container.querySelector(
                '.agreement-header'
            );

        if (agreementHeader) {this.protectedAgreementHeaderHtml =
                agreementHeader.outerHTML;
        }
    }


    /**
     * Restores the original hidden agreement header before the
     * agreement is stored/sent.
     *
     * The user edits only the agreement body, while the original
     * header remains protected.
     */
    restoreProtectedAgreementHeader(html) {
        const container =
            document.createElement('div');

        container.innerHTML =
            html || '';

        const agreementRoot =
            this.ensureAgreementRoot(
                container
            );

        /*
        * Remove any header that might have been introduced by
        * rich-text normalization.
        */
        const existingHeader =
            agreementRoot.querySelector(
                '.agreement-header'
            );

        if (existingHeader) {
            existingHeader.remove();
        }

        if (
            !this.protectedAgreementHeaderHtml
        ) {
            return container.innerHTML;
        }

        const holder =
            document.createElement('div');

        holder.innerHTML =
            this.protectedAgreementHeaderHtml;

        const protectedHeader =
            holder.firstElementChild;

        if (protectedHeader) {
            agreementRoot.insertBefore(
                protectedHeader.cloneNode(true),
                agreementRoot.firstChild
            );
        }

        return container.innerHTML;
    }

    handleAgreementChange(event) {
        if (!event || !event.target) {
            return;
        }

        /*
        * Ignore the onchange event produced by our own
        * protected-content restoration.
        */
        if (this.isRestoringProtectedContent) {
            this.isRestoringProtectedContent = false;
            return;
        }

        const editedBodyHtml = event.target.value || '';

        /*
        * The editor contains only the visible agreement body.
        *
        * Restore the protected original header before performing
        * the existing Project Information / Vendor Details
        * protection checks.
        */
        const editedHtml = this.restoreProtectedAgreementHeader(editedBodyHtml);

        /*
        * Keep normal typing immediate.
        */
        // if (!editedHtml) {
        //     this.agreementHtml = editedHtml;
        //     return;
        // }

        /*
        * Parse only once and perform lightweight comparisons.
        */
        const protectionState =
            this.getProtectedAgreementState(
                editedHtml
            );

        /*
        * -----------------------------------------------------
        * NORMAL EDIT
        * -----------------------------------------------------
        *
        * This is the important performance path.
        *
        * Bold, italic, text editing, lists, indentation,
        * alignment, etc. outside protected sections go
        * straight through without rebuilding the editor.
        */
        if (
            !protectionState.projectChanged &&
            !protectionState.vendorDetailsChanged
        ) {
            this.agreementHtml =
                editedHtml;

            return;
        }

        /*
        * -----------------------------------------------------
        * PROTECTED CONTENT WAS CHANGED
        * -----------------------------------------------------
        */
        const restoredHtml = this.restoreProtectedAgreementContent(editedHtml, protectionState.projectChanged, protectionState.vendorDetailsChanged);
        this.agreementHtml = restoredHtml;
        this.editableAgreementHtml = this.removeAgreementHeaderForPreview(restoredHtml);

        /*
        * Prevent a restoration-triggered onchange loop.
        */
        this.isRestoringProtectedContent = true;

        /*
        * Update the rich-text editor only when the user
        * actually attempted to alter protected content.
        */
        // if (
        //     event.target.value !==
        //     restoredHtml
        // ) {
        //     event.target.value =
        //         restoredHtml;
        // } else {
        //     this.isRestoringProtectedContent =
        //         false;
        // }

        const restoredEditorHtml = this.removeAgreementHeaderForPreview(restoredHtml);

        if (
            event.target.value !==
            restoredEditorHtml
        ) {
            event.target.value =
                restoredEditorHtml;
        } else {
            this.isRestoringProtectedContent =
                false;
        }
    }

    /**
     * Captures the original Project Information table and
     * Vendor Details section generated by Salesforce.
     */
    captureProtectedVendorAgreementSections(html) {
        this.protectedProjectInformationTableHtml = '';
        this.protectedVendorDetailsSectionHtml = '';
        this.protectedVendorDetailsTableHtml = '';

        this.protectedProjectInformationSignature = '';
        this.protectedVendorDetailsSignature = '';

        if (!html) {
            return;
        }

        /*
        * Parse the agreement only once.
        */
        const container =
            document.createElement('div');

        container.innerHTML = html;

        /*
        * -----------------------------------------------------
        * Project Information
        * -----------------------------------------------------
        */
        const projectTable =
            this.findProjectInformationTable(
                container
            );

        if (projectTable) {
            this.protectedProjectInformationTableHtml =
                projectTable.outerHTML;

            this.protectedProjectInformationSignature =
                this.getProtectedTableSignature(
                    projectTable
                );
        }

        /*
        * -----------------------------------------------------
        * Vendor Details
        * -----------------------------------------------------
        */
        const vendorDetailsSection =
            this.findVendorDetailsSection(
                container
            );

        const vendorDetailsTable =
            this.findVendorDetailsTable(
                container
            );

        if (vendorDetailsSection) {
            this.protectedVendorDetailsSectionHtml =
                vendorDetailsSection.outerHTML;
        }

        if (vendorDetailsTable) {
            this.protectedVendorDetailsTableHtml =
                vendorDetailsTable.outerHTML;

            this.protectedVendorDetailsSignature =
                this.getProtectedTableSignature(
                    vendorDetailsTable
                );
        }
    }


    /**
     * Finds the Project Information / reference table.
     * Class-based detection is attempted first.
     * A structural fallback is provided because
     * lightning-input-rich-text can sometimes remove classes.
     */
    findProjectInformationTable(container) {
        if (!container) {
            return null;
        }

        /*
        * Fastest / normal case.
        */
        const classBasedTable =
            container.querySelector(
                'table.reference-table'
            );

        if (classBasedTable) {
            return classBasedTable;
        }

        /*
        * Reliable fallback:
        *
        * Project Information is always the agreement table
        * that appears before "1. Parties".
        *
        * Do NOT identify it using its cell text because the
        * user may have already backspaced/deleted that text.
        */
        const firstSectionHeading =
            this.findHeadingByProtectedText(
                container,
                '1. PARTIES'
            );

        if (!firstSectionHeading) {
            return null;
        }

        const tables =
            Array.from(
                container.querySelectorAll('table')
            );

        /*
        * Find the last table that appears before 1. Parties.
        */
        const tablesBeforeParties =
            tables.filter((table) => {
                const position =
                    table.compareDocumentPosition(
                        firstSectionHeading
                    );

                return Boolean(
                    position &
                    Node.DOCUMENT_POSITION_FOLLOWING
                );
            });

        if (!tablesBeforeParties.length) {
            return null;
        }

        return tablesBeforeParties[
            tablesBeforeParties.length - 1
        ];
    }


    /**
     * Finds the Vendor Details block.
     * Normally generated as:
     * <div class="vendor-details">
     *     <h2>Vendor Details</h2>
     *     <table>...</table>
     * </div>
     */
    findVendorDetailsSection(container) {
        if (!container) {
            return null;
        }

        const classBasedSection =
            container.querySelector(
                '.vendor-details'
            );

        if (classBasedSection) {
            return classBasedSection;
        }

        /*
        * Fallback when the editor removes custom classes.
        */
        const headings =
            Array.from(
                container.querySelectorAll(
                    'h1, h2, h3, h4, h5, h6'
                )
            );

        const vendorDetailsHeading =
            headings.find((heading) => {
                return (
                    this.normalizeProtectedText(
                        heading.textContent
                    ) === 'VENDOR DETAILS'
                );
            });

        if (!vendorDetailsHeading) {
            return null;
        }

        let parent =
            vendorDetailsHeading.parentElement;

        /*
        * If the heading and table are still inside one wrapper,
        * protect that wrapper.
        */
        if (
            parent &&
            parent !== container &&
            parent.querySelector('table')
        ) {
            return parent;
        }

        /*
        * Otherwise construct protection around the heading's
        * containing block if possible.
        */
        return vendorDetailsHeading;
    }

    findVendorDetailsTable(container) {
        if (!container) {
            return null;
        }

        /*
        * Fast class-based lookup first.
        */
        const classBasedTable = container.querySelector('table.details-table');

        if (classBasedTable) {
            return classBasedTable;
        }

        /*
        * Structural fallback.
        *
        * lightning-input-rich-text may remove the original
        * details-table class, so identify the table by its
        * Salesforce-generated labels.
        */
        const tables =
            Array.from(
                container.querySelectorAll(
                    'table'
                )
            );

        return (
            tables.find((table) => {
                const signature =
                    this.getProtectedTableSignature(
                        table
                    );

                return (
                    signature.includes(
                        'VENDOR NAME'
                    ) &&
                    signature.includes(
                        'VENDOR EMAIL'
                    ) &&
                    signature.includes(
                        'VENDOR CONTACT NUMBER'
                    ) &&
                    signature.includes(
                        'VENDOR CATEGORY'
                    ) &&
                    signature.includes(
                        'ADDRESS'
                    ) &&
                    !signature.includes(
                        'AGREEMENT DATE'
                    )
                );
            }) || null
        );
    }


    /**
     * Finds a heading using normalized text.
     */
    findHeadingByProtectedText(container, expectedText) {
        if (!container || !expectedText) {
            return null;
        }

        const normalizedExpected = this.normalizeProtectedText(expectedText);

        const headings =
            Array.from(
                container.querySelectorAll(
                    'h1, h2, h3, h4, h5, h6'
                )
            );

        return (
            headings.find((heading) => {
                return (
                    this.normalizeProtectedText(
                        heading.textContent
                    ) === normalizedExpected
                );
            }) || null
        );
    }


    /**
     * Creates an element from the stored protected HTML.
     */
    createProtectedElementFromHtml(html) {
        if (!html) {
            return null;
        }

        const holder = document.createElement('div');
        holder.innerHTML = html;
        return holder.firstElementChild
            ? holder.firstElementChild.cloneNode(true)
            : null;
    }


    /**
     * Normalizes text used for section/table detection.
     */
    normalizeProtectedText(value) {
        return String(value || '')
            .replace(/\u00a0/g, ' ')
            .replace(/\s+/g, ' ')
            .trim()
            .toUpperCase();
    }

    handleEdit() {
        this.isEditing = true;
    }

    async handleSave() {
        this.isLoading = true;

        try {
            /*
            * Final protection before saving.
            */
            const protectedAgreementHtml = this.restoreProtectedAgreementContent(this.agreementHtml, true, true);
            const normalizedAgreementHtml = this.normalizeAgreementHtml(protectedAgreementHtml);
            const response = await saveAgreement({vendorOpportunityId: this.recordId, agreementHtml: normalizedAgreementHtml});
            this.agreementHtml = response.agreementHtml;
            this.captureProtectedAgreementHeader(this.agreementHtml);
            this.editableAgreementHtml = this.removeAgreementHeaderForPreview(this.agreementHtml);
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
                const protectedAgreementHtml = this.restoreProtectedAgreementContent(this.agreementHtml, true, true);
                const normalizedAgreementHtml = this.normalizeAgreementHtml(protectedAgreementHtml);
                const response = await saveAgreement({vendorOpportunityId: this.recordId, agreementHtml: normalizedAgreementHtml});

                this.agreementHtml = response.agreementHtml;
                this.captureProtectedAgreementHeader(this.agreementHtml);
                this.editableAgreementHtml = this.removeAgreementHeaderForPreview(this.agreementHtml);
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
    removeAgreementHeaderForPreview(htmlValue) {
        if (!htmlValue) {
            return '';
        }

        const container = document.createElement('div');
        container.innerHTML = htmlValue;
        const classBasedHeader = container.querySelector('.agreement-header');
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

        const container = document.createElement('div');
        container.innerHTML = htmlValue;
        const agreementRoot = this.ensureAgreementRoot(container);
        this.restoreAgreementHeader(agreementRoot);
        this.restoreAgreementTables(agreementRoot);
        this.restoreAgreementSections(agreementRoot);
        return container.innerHTML;
    }

    ensureAgreementRoot(container) {
        const existingRoot = container.querySelector('.agreement-page');

        if (existingRoot) {
            return existingRoot;
        }

        const agreementRoot = document.createElement('div');
        agreementRoot.className = 'agreement-page';

        while (container.firstChild) {
            agreementRoot.appendChild(
                container.firstChild
            );
        }

        container.appendChild(agreementRoot);
        return agreementRoot;
    }

    restoreAgreementHeader(agreementRoot) {
        let header = agreementRoot.querySelector('.agreement-header');

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

        header.classList.add('agreement-header');
        header.style.textAlign = 'center';
        header.style.width = '100%';

        if (companyElement) {
            companyElement.classList.add(
                'company-name'
            );

            companyElement.style.textAlign = 'center';
            companyElement.style.width = '100%';

            /*
             * Do not set display:block inline.
             * The unsigned Visualforce PDF must be able
             * to hide this value through .company-name.
             */
            companyElement.style.removeProperty('display');
            header.appendChild(companyElement);
        }

        if (titleElement) {
            titleElement.classList.add('agreement-title');
            titleElement.style.textAlign = 'center';
            titleElement.style.width = '100%';
            titleElement.style.removeProperty('display');
            header.appendChild(titleElement);
        }

        if (subtitleElement) {
            subtitleElement.classList.add(
                'agreement-subtitle'
            );

            subtitleElement.style.textAlign = 'center';
            subtitleElement.style.width = '100%';
            subtitleElement.style.removeProperty('display');
            header.appendChild(subtitleElement);
        }
    }

    restoreAgreementTables(agreementRoot) {
        const tables = Array.from(agreementRoot.querySelectorAll('table'));

        if (!tables.length) {
            return;
        }

        tables[0].classList.add('reference-table');

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

    restoreAgreementSections(agreementRoot) {
        const headings = Array.from(agreementRoot.querySelectorAll('h1, h2, h3'));

        headings.forEach((heading) => {
            const parent = heading.parentElement;

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

            const headingText = this.cleanText(heading.textContent);

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

    findLeafElementByText(container, expectedText) {
        const normalizedExpected = this.cleanText(expectedText).toLowerCase();
        const candidates = Array.from(container.querySelectorAll('div, p, span, h1, h2, h3'));
        return candidates.find((element) => {
            const elementText = this.cleanText(element.textContent).toLowerCase();

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

    getFirstElementInDocumentOrder(elements) {
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
        this.dispatchEvent(new CloseActionScreenEvent());
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

    getProtectedTableSignature(table) {
        if (!table) {
            return '';
        }

        const rows =
            Array.from(
                table.querySelectorAll(
                    'tr'
                )
            );

        return rows
            .map((row) => {
                const cells =
                    Array.from(
                        row.querySelectorAll(
                            'th, td'
                        )
                    );

                return cells
                    .map((cell) => {
                        return this.normalizeProtectedText(
                            cell.textContent
                        );
                    })
                    .join('||');
            })
            .join('|||');
    }

    getProtectedAgreementState(html) {
        const result = {
            container: null,
            projectChanged: false,
            vendorDetailsChanged: false
        };

        if (!html) {
            return result;
        }

        /*
        * Only ONE DOM parse per editor change.
        */
        const container = document.createElement('div');
        container.innerHTML = html;
        result.container = container;

        /*
        * -----------------------------------------------------
        * Project Information
        * -----------------------------------------------------
        */
        if (
            this.protectedProjectInformationSignature
        ) {
            const projectTable = this.findProjectInformationTable(container);

            result.projectChanged = !projectTable || this.getProtectedTableSignature(projectTable) !== this.protectedProjectInformationSignature;
        }

        /*
        * -----------------------------------------------------
        * Vendor Details
        * -----------------------------------------------------
        */
        if (
            this.protectedVendorDetailsSignature
        ) {
            const vendorHeading =
                this.findHeadingByProtectedText(
                    container,
                    'VENDOR DETAILS'
                );

            const vendorTable =
                this.findVendorDetailsTable(
                    container
                );

            result.vendorDetailsChanged =
                !vendorHeading ||
                !vendorTable ||
                this.getProtectedTableSignature(
                    vendorTable
                ) !==
                this.protectedVendorDetailsSignature;
        }

        return result;
    }

    restoreProtectedAgreementContent(html, restoreProjectInformation = true, restoreVendorDetails = true) {
        if (!html) {
            return html || '';
        }

        const container =
            document.createElement('div');

        container.innerHTML = html;

        /*
        * =====================================================
        * PROJECT INFORMATION
        * =====================================================
        */
        if (
            restoreProjectInformation &&
            this.protectedProjectInformationTableHtml
        ) {
            const currentProjectTable =
                this.findProjectInformationTable(
                    container
                );

            const protectedProjectTable =
                this.createProtectedElementFromHtml(
                    this.protectedProjectInformationTableHtml
                );

            if (protectedProjectTable) {

                /*
                * Normal case:
                * Project Information still exists but somebody
                * modified/deleted/formatted content inside it.
                */
                if (currentProjectTable) {
                    currentProjectTable.replaceWith(
                        protectedProjectTable
                    );
                }

                /*
                * Entire Project Information table was deleted.
                */
                else {
                    const firstSectionHeading =
                        this.findHeadingByProtectedText(
                            container,
                            '1. PARTIES'
                        );

                    if (firstSectionHeading) {
                        /*
                        * Usually 1. Parties is inside an
                        * agreement-section wrapper.
                        */
                        const sectionContainer =
                            firstSectionHeading.parentElement;

                        if (
                            sectionContainer &&
                            sectionContainer.parentNode
                        ) {
                            sectionContainer.parentNode.insertBefore(
                                protectedProjectTable,
                                sectionContainer
                            );
                        } else if (
                            firstSectionHeading.parentNode
                        ) {
                            firstSectionHeading.parentNode.insertBefore(
                                protectedProjectTable,
                                firstSectionHeading
                            );
                        }
                    }
                }
            }
        }

        /*
        * =====================================================
        * VENDOR DETAILS
        * =====================================================
        */
        if (
            restoreVendorDetails &&
            this.protectedVendorDetailsTableHtml
        ) {
            const currentVendorTable =
                this.findVendorDetailsTable(
                    container
                );

            const vendorHeading =
                this.findHeadingByProtectedText(
                    container,
                    'VENDOR DETAILS'
                );

            const protectedVendorTable =
                this.createProtectedElementFromHtml(
                    this.protectedVendorDetailsTableHtml
                );

            /*
            * Normal situation:
            * table remains but one of its values was changed.
            */
            if (
                currentVendorTable &&
                protectedVendorTable
            ) {
                currentVendorTable.replaceWith(
                    protectedVendorTable
                );
            }

            /*
            * Table was completely removed but heading remains.
            */
            else if (
                vendorHeading &&
                protectedVendorTable
            ) {
                vendorHeading.insertAdjacentElement(
                    'afterend',
                    protectedVendorTable
                );
            }

            /*
            * Entire Vendor Details block was removed.
            */
            else if (
                this.protectedVendorDetailsSectionHtml
            ) {
                const protectedVendorSection =
                    this.createProtectedElementFromHtml(
                        this.protectedVendorDetailsSectionHtml
                    );

                const signatureHeading =
                    this.findHeadingByProtectedText(
                        container,
                        'FOR THE VENDOR'
                    );

                if (
                    protectedVendorSection &&
                    signatureHeading
                ) {
                    let signatureContainer =
                        signatureHeading.parentElement;

                    if (
                        signatureContainer &&
                        signatureContainer.parentElement
                    ) {
                        signatureContainer =
                            signatureContainer.parentElement;
                    }

                    if (
                        signatureContainer &&
                        signatureContainer.parentNode
                    ) {
                        signatureContainer.parentNode
                            .insertBefore(
                                protectedVendorSection,
                                signatureContainer
                            );
                    }
                }
            }
        }

        return container.innerHTML;
    }
}