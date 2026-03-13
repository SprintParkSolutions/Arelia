import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import LightningConfirm from 'lightning/confirm';
import sendCatalogueEmail from '@salesforce/apex/OpportunityCatalogueEmailSender.sendCatalogueEmail';

export default class SendCatalogueLink extends LightningElement {
    @api recordId;

    // Initial send attempt
    handleSend() {
        sendCatalogueEmail({
            oppId: this.recordId,
            forceSend: false
        })
            .then(() => {
                this.showSuccess();
            })
            .catch(error => {
                // If already sent, ask for confirmation
                if (error?.body?.message === 'ALREADY_SENT') {
                    this.confirmResend();
                } else {
                    this.showError(error);
                }
            });
    }

    // Confirmation popup
    async confirmResend() {
        const result = await LightningConfirm.open({
            message: 'Catalogue link was already sent. Do you want to send it again?',
            variant: 'header',
            label: 'Resend Catalogue Link'
        });

        if (result) {
            this.resendCatalogue();
        } else {
            this.closeModal();
        }
    }

    // Resend logic
    resendCatalogue() {
        sendCatalogueEmail({
            oppId: this.recordId,
            forceSend: true
        })
            .then(() => {
                this.showSuccess();
            })
            .catch(error => {
                this.showError(error);
            });
    }

    handleCancel() {
        this.closeModal();
    }

    // Utility methods
    showSuccess() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Catalogue link sent successfully.',
                variant: 'success'
            })
        );
        this.closeModal();
    }

    showError(error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: error?.body?.message || 'Failed to send email.',
                variant: 'error'
            })
        );
    }

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}