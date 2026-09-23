import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getApprovalData from '@salesforce/apex/PaymentTermController.getApprovalData';
import submitDecision from '@salesforce/apex/PaymentTermController.submitDecision';
import AreliaSiteRedirectUrlLabel from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';
import LightningAlert from 'lightning/alert';
import LightningConfirm from 'lightning/confirm';

const USER_TYPE_MANAGER = 'Manager';
const USER_TYPE_CLIENT = 'Client';
const ACTION_APPROVE = 'Approve';
const ACTION_REJECT = 'Reject';
const STATUS_SENT_FOR_MANAGER_APPROVAL = 'Sent for Manager Approval';
const STATUS_SENT_FOR_CLIENT_APPROVAL = 'Sent for Client Approval';

export default class PaymentTermApproval extends LightningElement {
    @track approvalData;
    @track terms = [];
    @track comments = '';
    @track isLoading = true;
    @track error;
    @track showCommentBox = false;
    @track isProcessed = false;
    @track showSuccessModal = false;
    @track successMessage = '';

    recordId;
    userType;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference) {
            return;
        }

        this.recordId = currentPageReference.state.id;
        this.userType = currentPageReference.state.type || USER_TYPE_MANAGER;
        this.loadData();
    }

    loadData() {
        if (!this.recordId) {
            this.error = 'Invalid Link: Record ID missing.';
            this.isLoading = false;
            return;
        }

        getApprovalData({ recordId: this.recordId })
            .then((result) => {
                this.approvalData = result;
                this.terms = this.getPreparedTerms(result.terms);
                this.isProcessed = this.getProcessedState(result);
                this.isLoading = false;
            })
            .catch((error) => {
                this.error = this.getErrorMessage(
                    error,
                    'Error loading data. The record may be invalid.'
                );
                this.isLoading = false;
            });
    }

    getPreparedTerms(paymentTerms) {
        if (!paymentTerms) {
            return [];
        }

        return paymentTerms.map((term, index) => ({
            ...term,
            serialNumber: index + 1,
            Term_Label__c: term.Term_Label__c || term.Name
        }));
    }

    getProcessedState(result) {
        const status = result && result.opportunity
            ? result.opportunity.Payment_Terms_Status__c
            : '';

        return (
            (this.userType === USER_TYPE_MANAGER && status !== STATUS_SENT_FOR_MANAGER_APPROVAL) ||
            (this.userType === USER_TYPE_CLIENT && status !== STATUS_SENT_FOR_CLIENT_APPROVAL)
        );
    }

    handleCommentChange(event) {
        this.comments = event.target.value;
        event.target.setCustomValidity('');
        event.target.reportValidity();
    }

    async handleApproveClick() {
        this.comments = '';
        this.showCommentBox = false;

        const result = await LightningConfirm.open({
            message: 'Are you sure you want to APPROVE these payment terms? This action cannot be undone.',
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
        this.comments = '';
        this.clearTextareaValidation();
    }

    async handleRejectClick() {
        const trimmedComments = this.comments ? this.comments.trim() : '';

        if (!trimmedComments) {
            this.showTextareaValidation('Please enter remarks before submitting an amendment.');

            await LightningAlert.open({
                message: 'Please enter remarks before submitting a rejection.',
                theme: 'error',
                label: 'Validation Error'
            });

            return;
        }

        this.clearTextareaValidation();

        const result = await LightningConfirm.open({
            message: 'Are you sure you want to REQUEST CHANGES? The remarks will be sent to the team.',
            variant: 'header',
            label: 'Confirm Rejection',
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
                this.error = this.getErrorMessage(error, 'Error submitting decision.');
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
            return 'Payment terms have been successfully authorized.';
        }

        return 'Your amendment request has been submitted successfully.';
    }

    showTextareaValidation(message) {
        const inputField = this.template.querySelector('.native-amendment-textarea');

        if (inputField) {
            inputField.setCustomValidity(message);
            inputField.reportValidity();
        }
    }

    clearTextareaValidation() {
        const inputField = this.template.querySelector('.native-amendment-textarea');

        if (inputField) {
            inputField.setCustomValidity('');
            inputField.reportValidity();
        }
    }

    getErrorMessage(error, defaultMessage) {
        return error && error.body && error.body.message
            ? error.body.message
            : defaultMessage;
    }

    handleNavigateHome() {
        const redirectUrl = (AreliaSiteRedirectUrlLabel || '').trim();

        if (redirectUrl) {
            window.location.assign(redirectUrl);
        }
    }
}