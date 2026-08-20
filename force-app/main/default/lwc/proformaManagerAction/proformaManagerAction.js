import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import AreliaSiteRedirectUrlLabel from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';
import getInvoice from '@salesforce/apex/ProformaManagerController.getInvoiceById';
import submitDecision from '@salesforce/apex/ProformaManagerController.submitManagerDecision';

const ACTION_APPROVE = 'Approve';
const ACTION_REJECT = 'Reject';
const STATUS_APPROVED = 'Approved';
const STATUS_REJECTED = 'Rejected';

export default class ProformaManagerAction extends LightningElement {
    @track invoiceData;
    @track comments = '';
    @track isLoading = true;
    @track error;
    @track showCommentBox = false;
    @track showConfirmationModal = false;
    @track showSuccessModal = false;
    @track confirmationMessage = '';
    @track successMessage = '';

    pendingAction;
    recordId;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference) {
            return;
        }

        this.recordId = currentPageReference.state.id;
        this.loadData();
    }

    loadData() {
        if (!this.recordId) {
            this.error = 'Invalid Link: Record ID missing.';
            this.isLoading = false;
            return;
        }

        getInvoice({ recordId: this.recordId })
            .then((result) => {
                this.invoiceData = result;
                this.comments = result.comments || '';
                this.isLoading = false;
            })
            .catch(() => {
                this.error = 'Record Not Found or Access Denied.';
                this.isLoading = false;
            });
    }

    get isLocked() {
        return this.invoiceData &&
            (
                this.invoiceData.managerStatus === STATUS_APPROVED ||
                this.invoiceData.managerStatus === STATUS_REJECTED
            );
    }

    get managerStatusDisplay() {
        if (this.invoiceData) {
            return this.invoiceData.managerStatus;
        }

        return 'Loading...';
    }

    get statusBadgeClass() {
        if (!this.invoiceData) {
            return 'slds-badge';
        }

        if (this.invoiceData.managerStatus === STATUS_APPROVED) {
            return 'slds-badge slds-theme_success';
        }

        return 'slds-badge slds-theme_error';
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

        this.pendingAction = ACTION_APPROVE;
        this.confirmationMessage = 'Are you sure you want to approve this invoice for final sign-off?';
        this.showConfirmationModal = true;
    }

    handleSubmitRejectionClick() {
        const trimmedComments = this.comments ? this.comments.trim() : '';

        if (!trimmedComments) {
            this.showTextareaValidation('Please provide a reason for rejection.');
            return;
        }

        this.clearTextareaValidation();
        this.pendingAction = ACTION_REJECT;
        this.confirmationMessage = 'Are you sure you want to reject this invoice and request changes?';
        this.showConfirmationModal = true;
    }

    closeConfirmationModal() {
        this.showConfirmationModal = false;
        this.pendingAction = null;
    }

    handleConfirmYes() {
        this.showConfirmationModal = false;

        if (this.pendingAction) {
            this.submit(this.pendingAction);
        }
    }

    submit(action) {
        this.isLoading = true;
        this.error = null;

        submitDecision({
            recordId: this.recordId,
            action,
            comments: this.comments
        })
            .then(() => {
                this.handleSubmitSuccess(action);
            })
            .catch((error) => {
                this.error = error && error.body && error.body.message
                    ? error.body.message
                    : 'Unknown Error';
                this.isLoading = false;
            });
    }

    handleSubmitSuccess(action) {
        const managerStatus = action === ACTION_APPROVE ? STATUS_APPROVED : STATUS_REJECTED;

        this.isLoading = false;
        this.showCommentBox = false;
        this.pendingAction = null;

        this.invoiceData = {
            ...this.invoiceData,
            managerStatus
        };

        this.successMessage = this.getSuccessMessage(action);
        this.showSuccessModal = true;
    }

    getSuccessMessage(action) {
        if (action === ACTION_APPROVE) {
            return 'The invoice has been successfully approved and signed off.';
        }

        return 'The invoice has been rejected. Revision requests have been sent.';
    }

    showTextareaValidation(message) {
        const inputField = this.template.querySelector('.manager-remarks-textarea');

        if (inputField) {
            inputField.setCustomValidity(message);
            inputField.reportValidity();
        }
    }

    clearTextareaValidation() {
        const inputField = this.template.querySelector('.manager-remarks-textarea');

        if (inputField) {
            inputField.setCustomValidity('');
            inputField.reportValidity();
        }
    }

    handleSuccessClose() {
        const redirectUrl = (AreliaSiteRedirectUrlLabel || '').trim();

        if (redirectUrl) {
            window.location.assign(redirectUrl);
        }
    }
}