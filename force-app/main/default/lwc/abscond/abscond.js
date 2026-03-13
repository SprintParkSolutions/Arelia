import { LightningElement, api, track } from 'lwc';
import getEmailTemplatesByFolder from '@salesforce/apex/HandleVendorAbscondController.getEmailTemplatesByFolder';
import getAbscondVendorsAndClient from '@salesforce/apex/HandleVendorAbscondController.getAbscondVendorsAndClient';
import sendEmail from '@salesforce/apex/HandleVendorAbscondController.sendEmail';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class Abscond extends LightningElement {
    @api recordId;

    @track emailTemplates = [];
    @track templateOptions = [];
    @track selectedTemplateId;
    @track selectedTemplateDeveloperName;
    @track templateType; // 'Vendor' or 'Client'

    @track vendors = [];
    @track clientEmail;
    @track clientName;

    @track selectedEmails = [];
    @track selectedVendorIds = [];

    @track isScreen1 = true;
    @track isScreen2 = false;
    @track isLoading = false;

    connectedCallback() {
        this.loadEmailTemplates();
    }

    async loadEmailTemplates() {
        this.isLoading = true;
        try {
            const result = await getEmailTemplatesByFolder();
            this.emailTemplates = result;
            this.templateOptions = result.map(t => ({
                label: t.name,
                value: t.id
            }));
        } catch (error) {
            this.showToast('Error', 'Error loading email templates: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        const selected = this.emailTemplates.find(t => t.id === this.selectedTemplateId);
        this.selectedTemplateDeveloperName = selected?.developerName;

        // 🔹 Detect template type based on name
        if (selected.name.toLowerCase().includes('vendor')) {
            this.templateType = 'Vendor';
        } else if (selected.name.toLowerCase().includes('client')) {
            this.templateType = 'Client';
        } else {
            this.templateType = 'Other';
        }

        // Reset previous selections
        this.selectedEmails = [];
        this.selectedVendorIds = [];
    }

    get isNextDisabled() {
        return !this.selectedTemplateId;
    }

    async goToNextScreen() {
        this.isLoading = true;
        try {
            const result = await getAbscondVendorsAndClient({ opportunityId: this.recordId });
            this.vendors = result.vendors || [];
            this.clientEmail = result.clientEmail;
            this.clientName = result.clientName;

            this.isScreen1 = false;
            this.isScreen2 = true;
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    goToPreviousScreen() {
        this.isScreen2 = false;
        this.isScreen1 = true;
        this.selectedEmails = [];
        this.selectedVendorIds = [];
    }

    handleRecipientSelection(event) {
        const email = event.target.dataset.email;
        const recordId = event.target.dataset.id;

        if (event.target.checked) {
            if (!this.selectedEmails.includes(email)) {
                this.selectedEmails.push(email);
            }
            if (this.templateType === 'Vendor' && recordId && !this.selectedVendorIds.includes(recordId)) {
                this.selectedVendorIds.push(recordId);
            }
        } else {
            this.selectedEmails = this.selectedEmails.filter(e => e !== email);
            if (this.templateType === 'Vendor') {
                this.selectedVendorIds = this.selectedVendorIds.filter(id => id !== recordId);
            }
        }
    }

    get isSendDisabled() {
        return !this.selectedEmails.length;
    }

    async handleSendEmail() {
        this.isLoading = true;
        try {
            await sendEmail({
                templateId: this.selectedTemplateId,
                recipientEmails: this.selectedEmails,
                opportunityId: this.recordId,
                templateType: this.templateType,
                vendorAssignmentIds: this.selectedVendorIds
            });

            this.showToast('Success', `Emails sent successfully (${this.selectedEmails.length}).`, 'success');
            this.resetForm();
        } catch (error) {
            this.showToast('Error', 'Error sending email: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    resetForm() {
        this.isScreen1 = true;
        this.isScreen2 = false;
        this.selectedTemplateId = null;
        this.selectedEmails = [];
        this.selectedVendorIds = [];
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}