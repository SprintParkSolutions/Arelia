import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getBudgetReview from '@salesforce/apex/OpportunityBudgetReviewController.getBudgetReview';
import submitDecision from '@salesforce/apex/OpportunityBudgetReviewController.submitDecision';
import AreliaSiteRedirectUrlLabel from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';
import LightningAlert from 'lightning/alert';
import LightningConfirm from 'lightning/confirm';

const USER_TYPE_CLIENT = 'Client';
const ACTION_APPROVE = 'Approve';
const ACTION_REJECT = 'Reject';
const STATUS_SENT_FOR_CLIENT_APPROVAL = 'Sent for Client Approval';
const STATUS_CLIENT_APPROVED = 'Client Approved';
const STATUS_MANAGER_REQUESTED_CHANGES = 'Manager Requested Changes';

export default class BudgetReviewApproval extends LightningElement {
    @track approvalData;
    @track comments = '';
    @track isLoading = true;
    @track error;
    @track showCommentBox = false;
    @track isProcessed = false;
    @track showSuccessModal = false;
    @track successMessage = '';

    recordId;
    userType;
    currentStatus;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference) {
            return;
        }

        let id = currentPageReference.state.id;
        let type = currentPageReference.state.type;

        if (!id || !type) {
            const urlParams = new URLSearchParams(window.location.search);

            if (!id) {
                id = urlParams.get('id');
            }

            if (!type) {
                type = urlParams.get('type');
            }
        }

        this.recordId = id;
        this.userType = type || 'Manager';

        if (this.recordId) {
            this.loadData();
            return;
        }

        this.error = 'Invalid Link: Record ID missing.';
        this.isLoading = false;
    }

    loadData() {
        getBudgetReview({ opportunityId: this.recordId })
            .then((result) => {
                this.approvalData = result;
                this.currentStatus = result.opportunity.Budget_Review_Status__c;
                this.isProcessed = this.getProcessedState(this.currentStatus);
                this.isLoading = false;
            })
            .catch(() => {
                this.error = 'Error loading data.';
                this.isLoading = false;
            });
    }

    getProcessedState(status) {
        if (this.userType === USER_TYPE_CLIENT) {
            return status !== STATUS_SENT_FOR_CLIENT_APPROVAL;
        }

        return status !== STATUS_CLIENT_APPROVED && status !== STATUS_MANAGER_REQUESTED_CHANGES;
    }

    get isClient() {
        return this.userType === USER_TYPE_CLIENT;
    }

    get isRevised() {
        return this.approvalData &&
            this.approvalData.opportunity.Budget_Review_Client_Remarks__c;
    }

    get approveButtonLabel() {
        return this.isClient ? 'Approve' : 'Final Approve';
    }

    get clientName() {
        return this.approvalData && this.approvalData.opportunity.Primary_Contact__r
            ? this.approvalData.opportunity.Primary_Contact__r.Name
            : 'Valued Client';
    }

    get supervisorName() {
        if (this.approvalData && this.approvalData.opportunity.Supervisor_User__r) {
            const firstName = this.approvalData.opportunity.Supervisor_User__r.FirstName || '';
            const lastName = this.approvalData.opportunity.Supervisor_User__r.LastName || '';

            return `${firstName} ${lastName}`.trim();
        }

        return 'Supervisor';
    }

    get supervisorEmail() {
        return this.approvalData && this.approvalData.opportunity.Supervisor_User__r
            ? this.approvalData.opportunity.Supervisor_User__r.Email
            : '';
    }

    handleCommentChange(event) {
        this.comments = event.target.value;
        event.target.setCustomValidity('');
        event.target.reportValidity();
    }

    async handleApproveClick() {
        this.comments = '';
        this.showCommentBox = false;

        const message = this.isClient
            ? 'Are you sure you want to APPROVE this budget? This will send it to the Manager.'
            : 'Are you sure you want to provide FINAL APPROVAL? This will lock the budget.';

        const result = await LightningConfirm.open({
            message,
            variant: 'header',
            label: 'Confirm Approval',
            theme: 'success'
        });

        if (result) {
            this.submit(ACTION_APPROVE);
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

    async handleRejectClick() {
        const trimmedComments = this.comments ? this.comments.trim() : '';

        if (!trimmedComments) {
            this.showTextareaValidation('Please enter remarks before submitting the request.');

            await LightningAlert.open({
                message: 'Please enter remarks.',
                theme: 'error',
                label: 'Validation Error'
            });

            return;
        }

        this.clearTextareaValidation();

        const result = await LightningConfirm.open({
            message: 'Are you sure you want to request changes?',
            variant: 'header',
            label: 'Confirm Request',
            theme: 'warning'
        });

        if (result) {
            this.submit(ACTION_REJECT);
        }
    }

    submit(action) {
        this.isLoading = true;
        this.error = null;

        const decisionData = {
            userType: this.userType,
            action,
            comments: this.comments
        };

        submitDecision({
            recordId: this.recordId,
            data: decisionData
        })
            .then(() => {
                this.handleSubmitSuccess(action);
            })
            .catch((error) => {
                this.isLoading = false;
                this.error = error && error.body && error.body.message
                    ? error.body.message
                    : 'Error submitting decision.';
            });
    }

    handleSubmitSuccess(action) {
        this.isLoading = false;
        this.isProcessed = true;
        this.showCommentBox = false;
        this.successMessage = this.getSuccessMessage(action);
        this.showSuccessModal = true;
    }

    getSuccessMessage(action) {
        if (action === ACTION_APPROVE) {
            return this.isClient
                ? 'Your budget approval has been successfully recorded and sent to the Manager for final sign-off.'
                : 'The budget has been successfully approved and locked.';
        }

        return 'Your revision request has been submitted successfully.';
    }

    showTextareaValidation(message) {
        const inputField = this.template.querySelector('.budget-remarks-textarea');

        if (inputField) {
            inputField.setCustomValidity(message);
            inputField.reportValidity();
        }
    }

    clearTextareaValidation() {
        const inputField = this.template.querySelector('.budget-remarks-textarea');

        if (inputField) {
            inputField.setCustomValidity('');
            inputField.reportValidity();
        }
    }

    handleNavigateHome() {
        const redirectUrl = (AreliaSiteRedirectUrlLabel || '').trim();

        if (redirectUrl) {
            window.location.assign(redirectUrl);
        }
    }
}