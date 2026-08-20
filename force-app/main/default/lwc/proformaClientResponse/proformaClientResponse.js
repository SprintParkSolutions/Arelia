import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import AreliaSiteRedirectUrlLabel from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';
import getInvoice from '@salesforce/apex/ProformaInvoiceController.getInvoiceById';
import submitDecision from '@salesforce/apex/ProformaInvoiceController.submitClientDecision';

const STATUS_APPROVED = 'Approved';
const STATUS_CHANGES_REQUESTED = 'Changes Requested';

export default class ProformaClientResponse extends LightningElement {
    @track invoiceData;
    @track comments = '';
    @track isLoading = true;
    @track isSubmitted = false;
    @track error;
    @track showCommentBox = false;
    @track showConfirmationModal = false;
    @track showSuccessModal = false;
    @track confirmationMessage = '';
    @track successMessage = '';

    recordId;
    pendingStatus;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference) {
            return;
        }

        this.recordId = currentPageReference.state.id;
        this.loadInvoice();
    }

    loadInvoice() {
        if (!this.recordId) {
            this.error = 'Invalid Link: Record ID missing.';
            this.isLoading = false;
            return;
        }

        getInvoice({ recordId: this.recordId })
            .then((result) => {
                this.invoiceData = result;
                this.isSubmitted = this.isFinalStatus(result.status);
                this.isLoading = false;
            })
            .catch(() => {
                this.error = 'Invalid Link or Record Not Found.';
                this.isLoading = false;
            });
    }

    get statusBadgeClass() {
        const currentStatus = this.invoiceData ? this.invoiceData.status : '';

        if (currentStatus === STATUS_APPROVED) {
            return 'slds-badge slds-theme_success';
        }

        if (currentStatus === STATUS_CHANGES_REQUESTED) {
            return 'slds-badge slds-theme_error';
        }

        return 'slds-badge';
    }

    isFinalStatus(status) {
        return status === STATUS_APPROVED || status === STATUS_CHANGES_REQUESTED;
    }

    handleCommentChange(event) {
        this.comments = event.target.value;
        event.target.setCustomValidity('');
        event.target.reportValidity();

        if (this.error) {
            this.error = null;
        }
    }

    handleRequestChangesClick() {
        this.showCommentBox = true;
        this.clearTextareaValidation();
    }

    handleBackClick() {
        this.showCommentBox = false;
        this.clearTextareaValidation();
    }

    handleApproveClick() {
        if (this.showCommentBox) {
            this.showCommentBox = false;
        }

        this.pendingStatus = STATUS_APPROVED;
        this.confirmationMessage = 'Are you sure you want to approve this invoice?';
        this.showConfirmationModal = true;
    }

    handleSubmitChangesClick() {
        const trimmedComments = this.comments ? this.comments.trim() : '';

        if (!trimmedComments) {
            this.showTextareaValidation('Please provide comments before requesting changes.');
            return;
        }

        this.clearTextareaValidation();
        this.pendingStatus = STATUS_CHANGES_REQUESTED;
        this.confirmationMessage = 'Are you sure you want to submit these changes?';
        this.showConfirmationModal = true;
    }

    closeConfirmationModal() {
        this.showConfirmationModal = false;
        this.pendingStatus = null;
    }

    handleConfirmYes() {
        this.showConfirmationModal = false;

        if (this.pendingStatus) {
            this.submit(this.pendingStatus);
        }
    }

    submit(status) {
        this.isLoading = true;
        this.error = null;

        submitDecision({
            recordId: this.recordId,
            status,
            comments: this.comments
        })
            .then(() => {
                this.handleSubmitSuccess(status);
            })
            .catch((error) => {
                this.error = error && error.body && error.body.message
                    ? error.body.message
                    : 'Error submitting decision.';
                this.isLoading = false;
            });
    }

    handleSubmitSuccess(status) {
        this.isLoading = false;
        this.isSubmitted = true;
        this.showCommentBox = false;
        this.pendingStatus = null;

        this.invoiceData = {
            ...this.invoiceData,
            status,
            comments: this.comments
        };

        this.successMessage = this.getSuccessMessage(status);
        this.showSuccessModal = true;
    }

    getSuccessMessage(status) {
        if (status === STATUS_APPROVED) {
            return 'The invoice has been successfully approved.';
        }

        return 'Your revision request has been submitted successfully.';
    }

    showTextareaValidation(message) {
        const inputField = this.template.querySelector('.change-textarea');

        if (inputField) {
            inputField.setCustomValidity(message);
            inputField.reportValidity();
        }
    }

    clearTextareaValidation() {
        const inputField = this.template.querySelector('.change-textarea');

        if (inputField) {
            inputField.setCustomValidity('');
            inputField.reportValidity();
        }
    }

    handleSuccessClose() {
        const redirectUrl = (AreliaSiteRedirectUrlLabel || '').trim();

        if (redirectUrl) {
            window.location.assign(redirectUrl);
            return;
        }

        this.showSuccessModal = false;
    }
}