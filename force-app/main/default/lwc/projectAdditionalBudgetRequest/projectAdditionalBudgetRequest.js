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

  uploadedFiles = []; // {name, base64}
  pendingFileReads = []; // Promises for reads still in progress

  amountLabel = 'Additional Budget';
  reasonLabel = 'Reason';

  // lightning-input type="file" accept expects a comma-separated string, not an array -
  // binding an array here produced a browser console warning ("Invalid attribute value for
  // accept") and left the underlying native file input in a state where the selected File
  // reference didn't carry real data through to Apex.
  acceptedFormats = '.pdf,.png,.jpg,.jpeg,.doc,.docx,.xls,.xlsx';

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

  handleFileChange(event) {
    // lightning-input type="file" exposes the selection on both event.target.files and
    // event.detail.files. Inside this Experience Cloud site's Locker/LWS-wrapped context,
    // event.target.files has been observed to yield File references that produce empty
    // data (blank name and content) from every read API tried (FileReader, arrayBuffer) -
    // event.detail.files is a separate channel that doesn't go through the same wrapping,
    // so prefer it and only fall back to event.target.files if it isn't present.
    const files = (event.detail && event.detail.files && event.detail.files.length)
      ? event.detail.files
      : event.target.files;
    if (!files || !files.length) return;

    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      this.uploadedFiles = [
        ...this.uploadedFiles,
        { name: file && file.name ? file.name : '(no name)' }
      ];
      const entryIndex = this.uploadedFiles.length - 1;

      if (!file || !file.name || !file.size) {
        this.error = `The selected file could not be read (no data). Please remove it and try attaching it again.`;
        continue;
      }
      // Track each read so handleSubmit can wait for it to finish instead of racing it.
      const readPromise = this.readFileAsBase64(file)
        .then((base64) => {
          if (!base64) {
            throw new Error(`"${file.name}" could not be read (empty file data).`);
          }
          const updated = [...this.uploadedFiles];
          updated[entryIndex] = { name: file.name, base64 };
          this.uploadedFiles = updated;
        });
      this.pendingFileReads = [...this.pendingFileReads, readPromise];
    }
  }

  async readFileAsBase64(file) {
    const buffer = await file.arrayBuffer();
    return this.arrayBufferToBase64(buffer);
  }

  arrayBufferToBase64(buffer) {
    let binary = '';
    const bytes = new Uint8Array(buffer);
    // Chunked to avoid a call-stack overflow from String.fromCharCode.apply on large files.
    const chunkSize = 0x8000;
    for (let i = 0; i < bytes.length; i += chunkSize) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
    }
    return btoa(binary);
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async handleSubmit() {
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

    if (this.pendingFileReads.length) {
      try {
        await Promise.all(this.pendingFileReads);
      } catch (e) {
        this.isBusy = false;
        this.error = this.normalizeError(e) || 'Failed to read one or more attached files. Please remove and re-attach them, then try again.';
        return;
      } finally {
        this.pendingFileReads = [];
      }
    }

    // Sent as a JSON string, not the raw array - passing a custom Apex wrapper type
    // (List<FileData>) directly as an @AuraEnabled parameter fails to deserialize from this
    // site (fields arrive blank). A plain String parameter, deserialized manually in Apex,
    // sidesteps that entirely.
    submitRequest({
      projectId: this.recordId,
      amount: this.amount,
      reason: this.reason,
      filesJson: JSON.stringify(this.uploadedFiles.map((f) => ({ name: f.name, base64: f.base64 })))
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