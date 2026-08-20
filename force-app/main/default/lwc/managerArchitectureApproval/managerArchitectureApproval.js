import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import AreliaSiteRedirectUrlLabel from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';
import getDesignById from '@salesforce/apex/ManagerApprovalController.getDesignById';
import submitManagerDecision from '@salesforce/apex/ManagerApprovalController.submitManagerDecision';

export default class ManagerArchitectureApproval extends LightningElement {
    @track designData;
    @track isLoading = false;
    @track showConfirmationModal = false;
    @track showSuccessModal = false;

    recordId;
    error;
    comments = '';
    showCommentBox = false;
    isFinalized = false;
    confirmationMessage = '';
    successMessage = '';
    pendingAction;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference) {
            return;
        }

        this.recordId =
            currentPageReference.state.id ||
            currentPageReference.state.recordId ||
            currentPageReference.state.c__id ||
            currentPageReference.state.c__recordId;

        if (this.recordId) {
            this.loadData();
        } else {
            this.error = 'Invalid Link: Record ID missing.';
        }
    }

    loadData() {
        this.isLoading = true;
        this.error = null;

        getDesignById({ recordId: this.recordId })
            .then((data) => {
                this.designData = data;
                this.isFinalized = this.isManagerFinalStatus(data.status);
                this.isLoading = false;
            })
            .catch((error) => {
                this.error = this.getErrorMessage(error, 'Invalid Link or Record not found.');
                this.isLoading = false;
            });
    }

    get isActionAllowed() {
        return this.designData && !this.isFinalized;
    }

    get hasManagerComments() {
        return this.designData && this.designData.comments;
    }

    get decisionText() {
        if (!this.designData || !this.designData.status) {
            return 'Pending';
        }

        return this.designData.status;
    }

    get decisionClass() {
        if (!this.designData || !this.designData.status) {
            return 'decision-pill pending-pill';
        }

        const normalizedStatus = this.designData.status.toLowerCase();

        if (normalizedStatus.includes('approved')) {
            return 'decision-pill approved-pill';
        }

        if (normalizedStatus.includes('rejected') || normalizedStatus.includes('revise')) {
            return 'decision-pill rejected-pill';
        }

        return 'decision-pill pending-pill';
    }

    handleApproveClick() {
        this.error = null;
        this.comments = '';
        this.showCommentBox = false;
        this.pendingAction = 'Approve';
        this.confirmationMessage = 'Are you sure you want to approve this design for final sign-off?';
        this.showConfirmationModal = true;
    }

    handleRequestChangesClick() {
        this.error = null;
        this.showCommentBox = true;
        this.pendingAction = null;
    }

    handleBackClick() {
        this.error = null;
        this.comments = '';
        this.showCommentBox = false;
        this.clearTextareaValidation();
    }

    handleCommentChange(event) {
        this.comments = event.target.value;
        this.clearTextareaValidation();
    }

    handleSubmitRejectionClick() {
        const trimmedComments = this.comments ? this.comments.trim() : '';

        if (!trimmedComments) {
            const inputField = this.template.querySelector('.native-manager-textarea');

            if (inputField) {
                inputField.setCustomValidity('Please provide a reason for rejection.');
                inputField.reportValidity();
            }

            return;
        }

        this.comments = trimmedComments;
        this.pendingAction = 'Reject';
        this.confirmationMessage = 'Are you sure you want to reject this design and request changes?';
        this.showConfirmationModal = true;
    }

    closeConfirmationModal() {
        this.showConfirmationModal = false;
        this.pendingAction = null;
    }

    handleConfirmYes() {
        if (!this.pendingAction) {
            this.closeConfirmationModal();
            return;
        }

        const actionToSubmit = this.pendingAction;
        this.showConfirmationModal = false;
        this.pendingAction = null;
        this.submitDecision(actionToSubmit);
    }

    submitDecision(action) {
        this.error = null;
        this.isLoading = true;

        submitManagerDecision({
            recordId: this.recordId,
            action: action,
            comments: this.comments
        })
            .then(() => {
                this.isLoading = false;
                this.isFinalized = true;
                this.showCommentBox = false;

                this.designData = {
                    ...this.designData,
                    status: action === 'Approve' ? 'Manager Approved' : 'Manager Rejected',
                    comments: this.comments
                };

                this.successMessage =
                    action === 'Approve'
                        ? 'The design has been successfully approved and finalized.'
                        : 'The design has been rejected. Revision request has been sent to the team.';

                this.showSuccessModal = true;
            })
            .catch((error) => {
                this.error = this.getErrorMessage(error, 'Error submitting decision.');
                this.isLoading = false;
            });
    }

    handleSuccessClose() {
        const redirectUrl = (AreliaSiteRedirectUrlLabel || '').trim();

        if (redirectUrl) {
            window.location.assign(redirectUrl);
        }
    }

    clearTextareaValidation() {
        const inputField = this.template.querySelector('.native-manager-textarea');

        if (inputField) {
            inputField.setCustomValidity('');
            inputField.reportValidity();
        }
    }

    isManagerFinalStatus(statusValue) {
        if (!statusValue) {
            return false;
        }

        const normalizedStatus = statusValue.toLowerCase();

        return (
            normalizedStatus.includes('manager approved') ||
            normalizedStatus.includes('manager rejected') ||
            normalizedStatus.includes('manager revise') ||
            normalizedStatus.includes('manager requested') ||
            normalizedStatus.includes('final sign-off') ||
            normalizedStatus.includes('finalized')
        );
    }

    getErrorMessage(error, fallbackMessage) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }

        if (error && error.message) {
            return error.message;
        }

        return fallbackMessage;
    }
}