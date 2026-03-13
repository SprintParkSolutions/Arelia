import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import submitRequest from '@salesforce/apex/ProjectAdditionalBudgetController.submitRequest';
import getFieldSetFields from '@salesforce/apex/ProjectAdditionalBudgetController.getFieldSetFields';

export default class ProjectAdditionalBudgetRequest extends LightningElement {
  @api recordId;

  isBusy = false;
  error;

  amount;
  reason;

  uploadedFiles = []; // {name, documentId}
  contentDocumentIds = [];

  amountLabel = 'Additional Budget';
  reasonLabel = 'Reason';

  acceptedFormats = ['.pdf', '.png', '.jpg', '.jpeg', '.doc', '.docx', '.xls', '.xlsx'];

  get submitLabel() {
    return this.isBusy ? 'Submitting...' : 'Submit';
  }

  connectedCallback() {
    getFieldSetFields()
      .then((fields) => {
        (fields || []).forEach((f) => {
          if (f?.apiName === 'Pending_Additional_Amount__c' && f?.label) this.amountLabel = f.label;
          if (f?.apiName === 'Pending_Additional_Reason__c' && f?.label) this.reasonLabel = f.label;
        });
      })
      .catch(() => {});
  }

  onAmount(e) {
    this.amount = e.target.value ? Number(e.target.value) : null;
  }

  onReason(e) {
    this.reason = e.target.value;
  }

  handleUploadFinished(event) {
    const files = event.detail.files || [];
    files.forEach((f) => {
      this.uploadedFiles = [...this.uploadedFiles, { name: f.name, documentId: f.documentId }];
      this.contentDocumentIds = [...this.contentDocumentIds, f.documentId];
    });
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  handleSubmit() {
    this.error = null;

    if (!this.recordId) {
      this.error = 'Record Id not found.';
      return;
    }
    if (!this.amount || this.amount <= 0) {
      this.error = 'Enter valid amount.';
      return;
    }
    if (!this.reason || !this.reason.trim()) {
      this.error = 'Enter reason.';
      return;
    }

    this.isBusy = true;

    submitRequest({
      projectId: this.recordId,
      amount: this.amount,
      reason: this.reason,
      contentDocumentIds: this.contentDocumentIds
    })
      .then(() => {
        this.dispatchEvent(
          new ShowToastEvent({
            title: 'Submitted',
            message: 'Request sent for manager approval (with documents, if uploaded).',
            variant: 'success'
          })
        );
        this.dispatchEvent(new CloseActionScreenEvent());
      })
      .catch((e) => {
        this.error = this.normalizeError(e);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  normalizeError(e) {
    if (!e) return 'Unknown error';
    if (Array.isArray(e.body)) return e.body.map((x) => x.message).join(', ');
    if (e.body?.message) return e.body.message;
    return e.message || 'Unknown error';
  }
}