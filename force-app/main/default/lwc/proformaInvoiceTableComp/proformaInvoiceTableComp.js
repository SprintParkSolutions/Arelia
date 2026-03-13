import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import init from '@salesforce/apex/InvoiceService.init';
import saveDraftJson from '@salesforce/apex/InvoiceService.saveDraftJson';
import submitJson from '@salesforce/apex/InvoiceService.submitJson';

import INVOICE_LINE_OBJECT from '@salesforce/schema/Invoice_Line__c';
import SECTION_TYPE_FIELD from '@salesforce/schema/Invoice_Line__c.Section_Type__c';
import ELECTRICAL_MODE_FIELD from '@salesforce/schema/Invoice_Line__c.Electrical_Mode__c';

import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

function uid() { return Math.random().toString(16).slice(2) + Date.now().toString(16); }
function toNum(v) { const n = Number(v); return Number.isFinite(n) ? n : 0; }
function round2(v) { return (Math.round((toNum(v) + Number.EPSILON) * 100) / 100).toFixed(2); }
function isOppId(id) { return !!id && typeof id === 'string' && id.startsWith('006'); }

function canonType(raw) {
    const t = (raw || '').toString().trim().toUpperCase();
    if (t === 'WOOD' || t.includes('WOOD')) return 'WOOD';
    if (t.includes('ELECTRIC')) return 'ELECTRICAL';
    if (t.includes('CIVIL')) return 'WOOD';      // civil behaves like wood
    if (t.includes('OTHER')) return 'OTHER';
    return 'OTHER';
}

const METERS_PER_COIL = 90;

export default class ProformaInvoiceTableComp extends LightningElement {
    @api recordId;

    @track loading = false;
    @track showForm = false;
    @track resolvedOppId = null;

    @track showSuccess = false;
    @track successInvoiceId = null;

    draftInvoiceId = null;

    @track header = { clientName: '', phone: '', clientAddress: '', invoiceDate: '', invoiceNo: '' };
    @track gstPercent = 9;

    @track sections = [];
    @track materials = [];
    @track notIncluded = [];

    @track sectionTypeOptions = [];
    @track electricalModeOptions = [];

    get showPicker() { return !this.showForm; }
    get opportunityId() { return isOppId(this.resolvedOppId) ? this.resolvedOppId : null; }
    get selectedOpportunityIdLabel() { return this.opportunityId || ''; }

    get sectionsEmpty() { return !this.sections || this.sections.length === 0; }
    get materialsEmpty() { return !this.materials || this.materials.length === 0; }
    get notIncludedEmpty() { return !this.notIncluded || this.notIncluded.length === 0; }

    @wire(getObjectInfo, { objectApiName: INVOICE_LINE_OBJECT })
    objInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objInfo.data.defaultRecordTypeId',
        fieldApiName: SECTION_TYPE_FIELD
    })
    wiredSectionTypes({ data, error }) {
        if (data?.values) {
            this.sectionTypeOptions = data.values.map(v => ({ label: v.label, value: v.value }));
        } else if (error) {
            this.toast('Error', 'Failed to load Section Type picklist.', 'error');
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$objInfo.data.defaultRecordTypeId',
        fieldApiName: ELECTRICAL_MODE_FIELD
    })
    wiredElectricalModes({ data, error }) {
        if (data?.values) {
            this.electricalModeOptions = data.values.map(v => ({ label: v.label, value: v.value }));
        } else if (error) {
            this.toast('Error', 'Failed to load Electrical Mode picklist.', 'error');
        }
    }

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        const urlOppId = pageRef?.state?.c__oppId;
        if (!isOppId(this.recordId) && isOppId(urlOppId) && !this.resolvedOppId) {
            this.resolvedOppId = urlOppId;
            this.showForm = true;
            this.loadExisting();
        }
    }

    connectedCallback() {
        if (isOppId(this.recordId)) {
            this.resolvedOppId = this.recordId;
            this.showForm = true;
            this.loadExisting();
        }
    }

    handleOppChange(event) {
        const picked =
            event?.detail?.recordId ||
            event?.detail?.value ||
            event?.detail?.selectedRecordId ||
            event?.target?.value;

        this.resolvedOppId = isOppId(picked) ? picked : null;
    }

    async handleStart() {
        if (!this.opportunityId) {
            this.toast('Error', 'Please select an Opportunity to continue.', 'error');
            return;
        }
        this.showForm = true;
        await this.loadExisting();
    }

    handleBackToSearch() {
        if (isOppId(this.recordId)) return;
        this.showForm = false;
        this.resolvedOppId = null;

        this.draftInvoiceId = null;
        this.header = { clientName: '', phone: '', clientAddress: '', invoiceDate: '', invoiceNo: '' };
        this.gstPercent = 9;
        this.sections = [];
        this.materials = [];
        this.notIncluded = [];
    }

    getDefaultSectionType() {
        const hasWood = (this.sectionTypeOptions || []).some(o => (o.value || '').toUpperCase().includes('WOOD'));
        return hasWood ? (this.sectionTypeOptions.find(o => (o.value || '').toUpperCase().includes('WOOD'))?.value) : ((this.sectionTypeOptions?.[0]?.value) || 'Other Works');
    }

    getDefaultElectricalMode() {
        const hasCoils = (this.electricalModeOptions || []).some(o => o.value === 'COILS');
        return hasCoils ? 'COILS' : ((this.electricalModeOptions?.[0]?.value) || 'QTY');
    }

    // ✅ line models per canonical type
    newLineForType(sectionTypePicklistValue) {
        const st = canonType(sectionTypePicklistValue);

        const base = {
            id: uid(),
            category: '',
            item: '',
            brand: '',
            explanation: ''
        };

        if (st === 'WOOD') {
            return { ...base, l: 0, h: 0, qty: 0, sqft: '0.00', rate: 0, amount: '0.00' };
        }

        if (st === 'ELECTRICAL') {
            const mode = this.getDefaultElectricalMode();
            return {
                ...base,
                electricalMode: mode,
                coils: 0,
                meters: 0,
                qty: 0,
                rate: 0,
                amount: '0.00',
                disableCoils: (mode === 'QTY'),
                disableMeters: (mode === 'QTY'),
                readonlyMeters: (mode === 'COILS'),
                disableQty: (mode === 'COILS')
            };
        }

        // ✅ OTHER: manual amount only
        return { ...base, amount: '0.00' };
    }

    normalizeSectionFlags(sec) {
        const st = canonType(sec.sectionType);
        sec.isWood = (st === 'WOOD');
        sec.isElectrical = (st === 'ELECTRICAL');
        sec.isOther = (!sec.isWood && !sec.isElectrical);
        return sec;
    }

    newSection() {
        const pickVal = this.getDefaultSectionType();
        return this.normalizeSectionFlags({
            id: uid(),
            sectionName: '',
            sectionType: pickVal,
            subtotal: '0.00',
            isActive: false,
            sectionCardClass: 'sectionCard',
            lines: [this.newLineForType(pickVal)]
        });
    }

    async loadExisting() {
        if (!this.opportunityId) return;

        this.loading = true;
        try {
            const res = await init({ opportunityId: this.opportunityId });

            this.draftInvoiceId = null;
            this.header = { clientName: '', phone: '', clientAddress: '', invoiceDate: '', invoiceNo: '' };
            this.gstPercent = 9;
            this.sections = [];
            this.materials = [];
            this.notIncluded = [];

            if (res?.invoiceId) {
                this.draftInvoiceId = (res.status === 'Draft') ? res.invoiceId : null;

                this.header = {
                    clientName: res.header?.clientName || '',
                    phone: res.header?.phone || '',
                    clientAddress: res.header?.clientAddress || '',
                    invoiceDate: res.header?.invoiceDate || '',
                    invoiceNo: res.header?.invoiceNo || ''
                };
                this.gstPercent = (res.header?.gstPercent ?? 9);

                this.sections = (res.sections || []).map(s => {
                    const secPick = s.sectionType || 'Other Works';
                    const st = canonType(secPick);

                    const sec = {
                        id: uid(),
                        sectionName: s.sectionName || '',
                        sectionType: secPick,
                        subtotal: '0.00',
                        isActive: false,
                        sectionCardClass: 'sectionCard',
                        lines: (s.lines || []).map(l => {
                            if (st === 'WOOD') {
                                return {
                                    id: uid(),
                                    category: l.category || '',
                                    item: l.item || '',
                                    brand: l.brand || '',
                                    explanation: l.explanation || '',
                                    l: l.l || 0,
                                    h: l.h || 0,
                                    qty: l.qty || 0,
                                    sqft: '0.00',
                                    rate: l.rate || 0,
                                    amount: '0.00'
                                };
                            }
                            if (st === 'ELECTRICAL') {
                                const mode = (l.electricalMode || this.getDefaultElectricalMode());
                                return {
                                    id: uid(),
                                    category: l.category || '',
                                    item: l.item || '',
                                    brand: l.brand || '',
                                    explanation: l.explanation || '',
                                    electricalMode: mode,
                                    coils: l.coils || 0,
                                    meters: l.meters || 0,
                                    qty: l.qty || 0,
                                    rate: l.rate || 0,
                                    amount: '0.00'
                                };
                            }
                            // OTHER
                            return {
                                id: uid(),
                                category: l.category || '',
                                item: l.item || '',
                                brand: l.brand || '',
                                explanation: l.explanation || '',
                                amount: round2(l.amount || 0)
                            };
                        })
                    };

                    // if section exists but has no lines, keep 1 blank line
                    if (!sec.lines || sec.lines.length === 0) {
                        sec.lines = [this.newLineForType(secPick)];
                    }
                    return this.normalizeSectionFlags(sec);
                });

                this.materials = (res.materials || []).map(m => ({
                    id: uid(),
                    material: m.material || '',
                    brand: m.brand || '',
                    grade: m.grade || ''
                }));

                this.notIncluded = (res.notIncluded || []).map(n => ({
                    id: uid(),
                    text: n.text || ''
                }));
            } else {
                this.sections = [this.newSection()];
            }

            this.setActiveSection(0);
            this.recalculateAll();
        } catch (e) {
            this.toast('Error', e?.body?.message || e.message, 'error');
        } finally {
            this.loading = false;
        }
    }

    setActiveSection(index) {
        this.sections = this.sections.map((s, i) => {
            const sec = { ...s };
            sec.isActive = (i === index);
            sec.sectionCardClass = sec.isActive ? 'sectionCard sectionActive' : 'sectionCard';
            return sec;
        });
    }

    handleHeaderChange(event) {
        const field = event.target.dataset.field;
        this.header = { ...this.header, [field]: event.target.value };
    }

    handleGstChange(event) {
        this.gstPercent = toNum(event.target.value);
    }

    addSection() {
        const copy = [...this.sections, this.newSection()];
        this.sections = copy;
        this.setActiveSection(copy.length - 1);
        this.recalculateAll();
    }

    handleSectionChange(event) {
        const sIndex = Number(event.target.dataset.sindex);
        const field = event.target.dataset.field;
        const value = event.target.value;

        const copy = this.sections.map(s => ({ ...s, lines: (s.lines || []).map(l => ({ ...l })) }));
        const sec = copy[sIndex];
        if (!sec) return;

        sec[field] = value;

        if (field === 'sectionType') {
            // reset lines when type changes
            sec.lines = [this.newLineForType(value)];
            this.normalizeSectionFlags(sec);
        }

        this.sections = copy;
        this.setActiveSection(sIndex);
        this.recalculateAll();
    }

    deleteSection(event) {
        const sIndex = Number(event.currentTarget.dataset.sindex);
        const copy = [...this.sections];
        copy.splice(sIndex, 1);
        this.sections = copy;
        if (this.sections.length > 0) this.setActiveSection(Math.max(0, sIndex - 1));
        this.recalculateAll();
    }

    addLine(event) {
        const sIndex = Number(event.currentTarget.dataset.sindex);
        const copy = this.sections.map(s => ({ ...s, lines: (s.lines || []).map(l => ({ ...l })) }));
        const sec = copy[sIndex];
        if (!sec) return;

        sec.lines = [...sec.lines, this.newLineForType(sec.sectionType)];
        this.sections = copy;
        this.setActiveSection(sIndex);
        this.recalculateAll();
    }

    deleteLine(event) {
        const sIndex = Number(event.currentTarget.dataset.sindex);
        const lIndex = Number(event.currentTarget.dataset.lindex);

        const copy = this.sections.map(s => ({ ...s, lines: (s.lines || []).map(l => ({ ...l })) }));
        const sec = copy[sIndex];
        if (!sec) return;

        const lines = [...sec.lines];
        lines.splice(lIndex, 1);
        sec.lines = lines.length ? lines : [this.newLineForType(sec.sectionType)];

        this.sections = copy;
        this.setActiveSection(sIndex);
        this.recalculateAll();
    }

    handleLineChange(event) {
        const sIndex = Number(event.target.dataset.sindex);
        const lIndex = Number(event.target.dataset.lindex);
        const field = event.target.dataset.field;
        const value = event.target.value;

        const copy = this.sections.map(s => ({ ...s, lines: (s.lines || []).map(l => ({ ...l })) }));
        const sec = copy[sIndex];
        if (!sec) return;

        const line = sec.lines[lIndex];
        if (!line) return;

        line[field] = value;

        // electrical mode behavior
        if (canonType(sec.sectionType) === 'ELECTRICAL' && field === 'electricalMode') {
            const mode = (value || this.getDefaultElectricalMode());

            if (mode === 'COILS') {
                line.qty = 0;
                line.disableQty = true;

                line.disableCoils = false;
                line.disableMeters = false;
                line.readonlyMeters = true;

                line.meters = toNum(line.coils) * METERS_PER_COIL;
            } else {
                line.coils = 0;
                line.meters = 0;

                line.disableCoils = true;
                line.disableMeters = true;
                line.readonlyMeters = false;

                line.disableQty = false;
            }
        }

        this.sections = copy;
        this.setActiveSection(sIndex);
        this.recalculateAll();
    }

    recalculateAll() {
        const copy = this.sections.map(s => ({ ...s, lines: (s.lines || []).map(l => ({ ...l })) }));

        for (const sec of copy) {
            let sub = 0;
            const st = canonType(sec.sectionType);

            for (const l of sec.lines) {
                if (st === 'WOOD') {
                    const rate = toNum(l.rate);
                    const sqft = (toNum(l.l) * toNum(l.h) * toNum(l.qty)) / 144;
                    l.sqft = round2(sqft);
                    l.amount = round2(sqft * rate);
                    sub += toNum(l.amount);
                }
                else if (st === 'ELECTRICAL') {
                    const rate = toNum(l.rate);
                    const mode = l.electricalMode || this.getDefaultElectricalMode();
                    const isCoils = (mode === 'COILS');

                    l.disableCoils = !isCoils;
                    l.disableMeters = !isCoils;
                    l.readonlyMeters = isCoils;
                    l.disableQty = isCoils;

                    let amt = 0;
                    if (isCoils) {
                        l.meters = toNum(l.coils) * METERS_PER_COIL;
                        l.qty = 0;
                        amt = toNum(l.meters) * rate;
                    } else {
                        l.coils = 0;
                        l.meters = 0;
                        amt = toNum(l.qty) * rate;
                    }

                    l.amount = round2(amt);
                    sub += toNum(l.amount);
                }
                else {
                    // ✅ OTHER: manual amount
                    l.amount = round2(l.amount);
                    sub += toNum(l.amount);
                }
            }

            sec.subtotal = round2(sub);
            this.normalizeSectionFlags(sec);
        }

        this.sections = copy;
    }

    get totalAmount() {
        let sum = 0;
        for (const s of this.sections) sum += toNum(s.subtotal);
        return round2(sum);
    }

    get gstAmount() {
        return round2((toNum(this.totalAmount) * toNum(this.gstPercent)) / 100);
    }

    get grandTotalWithGst() {
        return round2(toNum(this.totalAmount) + toNum(this.gstAmount));
    }

    addMaterial() {
        this.materials = [...this.materials, { id: uid(), material: '', brand: '', grade: '' }];
    }
    removeMaterial(event) {
        const index = Number(event.currentTarget.dataset.index);
        const copy = [...this.materials];
        copy.splice(index, 1);
        this.materials = copy;
    }
    handleMaterialChange(event) {
        const index = Number(event.target.dataset.index);
        const field = event.target.dataset.field;
        const copy = this.materials.map(m => ({ ...m }));
        copy[index][field] = event.target.value;
        this.materials = copy;
    }

    addNotIncluded() {
        this.notIncluded = [...this.notIncluded, { id: uid(), text: '' }];
    }
    removeNotIncluded(event) {
        const index = Number(event.currentTarget.dataset.index);
        const copy = [...this.notIncluded];
        copy.splice(index, 1);
        this.notIncluded = copy;
    }
    handleNotIncludedChange(event) {
        const index = Number(event.target.dataset.index);
        const copy = this.notIncluded.map(n => ({ ...n }));
        copy[index].text = event.target.value;
        this.notIncluded = copy;
    }

    buildPayload(existingInvoiceId) {
        return {
            opportunityId: this.opportunityId,
            existingInvoiceId: existingInvoiceId || null,
            header: {
                clientName: this.header.clientName,
                phone: this.header.phone,
                clientAddress: this.header.clientAddress,
                invoiceDate: this.header.invoiceDate,
                invoiceNo: this.header.invoiceNo,
                gstPercent: toNum(this.gstPercent)
            },
            sections: (this.sections || []).map((s) => {
                const st = canonType(s.sectionType);

                return {
                    sectionName: s.sectionName || '',
                    sectionType: s.sectionType || 'Other Works',
                    lines: (s.lines || []).map((l) => {
                        if (st === 'WOOD') {
                            return {
                                category: l.category || '',
                                item: l.item || '',
                                brand: l.brand || '',
                                explanation: l.explanation || '',
                                l: toNum(l.l),
                                h: toNum(l.h),
                                qty: toNum(l.qty),
                                rate: toNum(l.rate)
                            };
                        }
                        if (st === 'ELECTRICAL') {
                            const mode = l.electricalMode || this.getDefaultElectricalMode();
                            return {
                                category: l.category || '',
                                item: l.item || '',
                                brand: l.brand || '',
                                explanation: l.explanation || '',
                                electricalMode: mode,
                                coils: (mode === 'COILS') ? toNum(l.coils) : 0,
                                meters: (mode === 'COILS') ? toNum(l.meters) : 0,
                                qty: (mode === 'QTY') ? toNum(l.qty) : 0,
                                rate: toNum(l.rate)
                            };
                        }
                        // ✅ OTHER
                        return {
                            category: l.category || '',
                            item: l.item || '',
                            brand: l.brand || '',
                            explanation: l.explanation || '',
                            amount: toNum(l.amount)
                        };
                    })
                };
            }),
            materials: (this.materials || []).map((m, idx) => ({
                material: m.material || '',
                brand: m.brand || '',
                grade: m.grade || '',
                sortOrder: idx + 1
            })),
            notIncluded: (this.notIncluded || []).map((n, idx) => ({
                text: n.text || '',
                sortOrder: idx + 1
            })),
            total: toNum(this.totalAmount),
            gstAmount: toNum(this.gstAmount),
            grandTotal: toNum(this.grandTotalWithGst)
        };
    }

    async handleSaveDraft() {
        if (!this.opportunityId) {
            this.toast('Error', 'Please select an Opportunity.', 'error');
            return;
        }
        if (this.loading) return;
        this.loading = true;

        try {
            const payloadJson = JSON.stringify(this.buildPayload(this.draftInvoiceId));
            const id = await saveDraftJson({ payloadJson });
            this.draftInvoiceId = id;
            this.toast('Saved', 'Draft saved successfully in Salesforce.', 'success');
        } catch (e) {
            this.toast('Error', e?.body?.message || e.message, 'error');
        } finally {
            this.loading = false;
        }
    }

    async handleSubmit() {
        if (!this.opportunityId) {
            this.toast('Error', 'Please select an Opportunity.', 'error');
            return;
        }
        if (this.loading) return;
        this.loading = true;

        try {
            const payloadJson = JSON.stringify(this.buildPayload(this.draftInvoiceId));
            const invoiceId = await submitJson({ payloadJson });

            this.successInvoiceId = invoiceId;
            this.showSuccess = true;

            this.draftInvoiceId = null;
            this.toast('Submitted', 'Invoice submitted successfully.', 'success');
        } catch (e) {
            this.toast('Error', e?.body?.message || e.message, 'error');
        } finally {
            this.loading = false;
        }
    }

    handleCloseSuccess() {
        this.showSuccess = false;
        window.location.reload();
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}