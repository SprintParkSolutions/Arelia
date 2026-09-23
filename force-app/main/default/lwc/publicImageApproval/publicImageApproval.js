import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import AreliaSiteRedirectUrlLabel from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';
import getFileByToken from '@salesforce/apex/ImageApprovalController.getFileByToken';
import submitDecision from '@salesforce/apex/ImageApprovalController.submitDecision';

const STATUS_APPROVED = 'Approved';
const STATUS_CHANGES_REQUESTED = 'Changes Requested';

export default class PublicImageApproval extends LightningElement {
    @track fileData;
    @track isLoading = false;
    @track showConfirmationModal = false;
    @track showSuccessModal = false;
    @track confirmationMessage = '';
    @track successMessage = '';

    token;
    error;
    comments = '';
    showCommentBox = false;
    isFinalized = false;
    pendingStatus;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference) {
            return;
        }

        this.token = currentPageReference.state.token;

        if (this.token) {
            this.loadData();
            return;
        }

        this.error = 'Invalid Link: Token missing.';
    }

    loadData() {
        getFileByToken({ token: this.token })
            .then((data) => {
                this.fileData = data;
                this.isFinalized = this.isFinalStatus(data.status);
            })
            .catch(() => {
                this.error = 'Invalid Link or Record not found.';
            });
    }

    get statusBadgeClass() {
        const currentStatus = this.fileData ? this.fileData.status : '';

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

    handleRequestChangesClick() {
        this.showCommentBox = true;
        this.clearTextareaValidation();
    }

    handleBackClick() {
        this.showCommentBox = false;
        this.clearTextareaValidation();
    }

    handleCommentChange(event) {
        this.comments = event.target.value;
        event.target.setCustomValidity('');
        event.target.reportValidity();
    }

    handleApproveClick() {
        if (this.showCommentBox) {
            this.showCommentBox = false;
        }

        this.pendingStatus = STATUS_APPROVED;
        this.confirmationMessage = 'Are you sure you want to approve this design?';
        this.showConfirmationModal = true;
    }

    handleSubmitChangesClick() {
        const trimmedComments = this.comments ? this.comments.trim() : '';

        if (!trimmedComments) {
            this.showTextareaValidation('Comments required for change requests.');
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
        this.error = null;
        this.isLoading = true;

        submitDecision({
            token: this.token,
            status,
            comments: this.comments
        })
            .then(() => {
                this.handleSubmitSuccess(status);
            })
            .catch(() => {
                this.error = 'Error submitting response. Please try again.';
                this.isLoading = false;
            });
    }

    handleSubmitSuccess(status) {
        this.isLoading = false;
        this.isFinalized = true;
        this.fileData = {
            ...this.fileData,
            status,
            comments: this.comments
        };

        this.successMessage = this.getSuccessMessage(status);
        this.showSuccessModal = true;
        this.pendingStatus = null;
    }

    getSuccessMessage(status) {
        if (status === STATUS_APPROVED) {
            return 'The design has been successfully approved. We will proceed to the next steps.';
        }

        return 'Your change request has been submitted successfully. Our team will review your notes.';
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