import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';

import updateAndSendEmail from '@salesforce/apex/ArchitectInfoController.updateAndSendEmail';

import ARCH_NAME_FIELD from '@salesforce/schema/Opportunity.Architect_Name__c';
import ARCH_EMAIL_FIELD from '@salesforce/schema/Opportunity.Architect_Email__c';
import ARCH_PHONE_FIELD from '@salesforce/schema/Opportunity.Architect_Contact__c';

const fields = [ARCH_NAME_FIELD, ARCH_EMAIL_FIELD, ARCH_PHONE_FIELD];

export default class ArchitectInfoComponent extends LightningElement {
    @api recordId; // Opportunity Id

    @track architectName = '';
    @track architectEmail = '';
    @track architectPhone = '';
    
    isLoading = false;

    // Fetch existing details to pre-populate the screen
    @wire(getRecord, { recordId: '$recordId', fields })
    wiredRecord({ error, data }) {
        if (data) {
            this.architectName = getFieldValue(data, ARCH_NAME_FIELD) || '';
            this.architectEmail = getFieldValue(data, ARCH_EMAIL_FIELD) || '';
            this.architectPhone = getFieldValue(data, ARCH_PHONE_FIELD) || '';
        } else if (error) {
            this.showToast('Error', 'Error loading record data', 'error');
        }
    }

    handleChange(event) {
        const field = event.target.dataset.field;
        if (field === 'name') this.architectName = event.target.value;
        if (field === 'email') this.architectEmail = event.target.value;
        if (field === 'phone') this.architectPhone = event.target.value;
    }

    handleSubmit() {
        // 1. Check validations (Regex and Required fields)
        const allValid = [...this.template.querySelectorAll('lightning-input')]
            .reduce((validSoFar, inputCmp) => {
                inputCmp.reportValidity();
                return validSoFar && inputCmp.checkValidity();
            }, true);

        if (!allValid) {
            return;
        }

        // 2. Call Apex
        this.isLoading = true;
        updateAndSendEmail({
            recordId: this.recordId,
            architectName: this.architectName,
            architectEmail: this.architectEmail,
            architectPhone: this.architectPhone
        })
        .then(() => {
            this.showToast('Success', 'Record updated and email sent successfully.', 'success');
            // Close the quick action modal if used as a Quick Action
            this.dispatchEvent(new CloseActionScreenEvent());
        })
        .catch(error => {
            this.showToast('Error', error.body ? error.body.message : error.message, 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
            })
        );
    }
}