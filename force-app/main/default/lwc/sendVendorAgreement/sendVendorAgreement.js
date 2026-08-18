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

        if (value && !this.hasLoadedAgreement) {
            this.hasLoadedAgreement = true;
            this.loadAgreement();
        }
    }

    get recordId() {
        return this._recordId;
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

    handleAgreementChange(event) {
        this.agreementHtml = event.target.value;
    }

    handleEdit() {
        this.isEditing = true;
    }

    async handleSave() {
        this.isLoading = true;

        try {
            const response = await saveAgreement({
                vendorOpportunityId: this.recordId,
                agreementHtml: this.agreementHtml
            });

            this.agreementHtml = response.agreementHtml;
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
                const response = await saveAgreement({
                    vendorOpportunityId: this.recordId,
                    agreementHtml: this.agreementHtml
                });

                this.agreementHtml = response.agreementHtml;
                this.isEditing = false;
            }

            await sendAgreement({
                vendorOpportunityId: this.recordId
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

    handleCancel() {
        this.closeAction();
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
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
}