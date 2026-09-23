import { LightningElement, api } from 'lwc';
import sendOpportunityPasswordEmail from '@salesforce/apex/PasswordManager.sendOpportunityPasswordEmail';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class OpportunityPasswordQuickAction extends LightningElement {
    @api recordId;
    successMessage;
    processing = false;

    handleSet() {
        this.sendEmail('SET');
    }

    handleForgot() {
        this.sendEmail('FORGOT');
    }

    sendEmail(mode) {
        this.processing = true;

        sendOpportunityPasswordEmail({
            opportunityId: this.recordId,
            mode: mode
        })
        .then(() => {
            this.successMessage = 'Email sent successfully.';
            setTimeout(() => {
                this.closeAction();
            }, 1500);
        })
        .catch(error => {
            alert(error.body?.message || 'Error sending email.');
        })
        .finally(() => {
            this.processing = false;
        });
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}