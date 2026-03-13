import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead';
import QUOTATION_TYPE_FIELD from '@salesforce/schema/Lead.Project_Request_Quotation_Type__c';

import getMasterData from '@salesforce/apex/InteriorMasterService.getMasterData';
import saveRequest from '@salesforce/apex/InteriorAutoProjectRequestService.saveRequest';
import fetchLeadForAutoRequest from '@salesforce/apex/InteriorAutoProjectRequestService.fetchLeadForAutoRequest';
import fetchExistingRequest from '@salesforce/apex/InteriorAutoProjectRequestService.fetchExistingRequest';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import SITE_URL from '@salesforce/label/c.Arelia_Site_Label';

import SUCCESS_IMG from '@salesforce/resourceUrl/Arelia_Projecect_Request_Sucess_Image';
import ALREADY_SUBMITTED_MSG from '@salesforce/label/c.Arelia_Project_Request_Already_Submitted';

export default class AreliaAutomaticProjectRequestComp extends LightningElement {
    @api leadId;
    @api quotationType;

    quotationTypeLabel; // ✅ label for UI display
    quotationTypeLabelByValue = {}; // { 'Manual': 'Custom Design' }

    @track currentStep = 1;

    allProjectTypes = [];
    allCategories = [];
    allRooms = [];
    allDesigns = [];
    allPlanLevels = [];

    firstName = '';
    lastName = '';
    email = '';
    phone = '';
    company = '';
    address = '';
    siteSpace = '';
    description = '';

    selectedProjectTypeId;
    selectedCategoryId;

    successImgUrl = SUCCESS_IMG;
    @track isAlreadySubmitted = false;
    submittedMessage = ALREADY_SUBMITTED_MSG;

    @track roomQuantities = {};

    @track instancePlanMap = {};     // { instanceKey: 'Standard' }
    @track instanceRoomSizeMap = {}; // { instanceKey: 520 }

    currentRoomInstanceKey;

    @track roomDesignMap = {}; // { instanceKey: { roomId, designId, planLevel, roomSizeSqft, templateSizeSqft, ratePerSqft, lineAmount } }

    totalBudget = 0;

    @track isImageModalOpen = false;
    modalImageUrl;
    modalTitle;

    isSaving = false;

    @track isInitLoading = true;
    hasInitLoaded = false;

    labels = { siteUrl: SITE_URL };
    AUTO_DEFAULT_ROOMS = true;


     // ✅ load Lead record type id
    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    leadInfo;

    // ✅ load picklist values (value + label)
    @wire(getPicklistValues, {
        recordTypeId: '$leadInfo.data.defaultRecordTypeId',
        fieldApiName: QUOTATION_TYPE_FIELD
    })
    wiredQuotationTypes({ data, error }) {
        if (data) {
            const map = {};
            (data.values || []).forEach((p) => {
                map[p.value] = p.label;
            });
            this.quotationTypeLabelByValue = map;

            // if value already present, compute label
            if (this.quotationType) {
                this.quotationTypeLabel = this.quotationTypeLabelByValue[this.quotationType] || this.quotationType;
            }
        } else if (error) {
            // fallback silently (don’t block UI)
            this.quotationTypeLabelByValue = {};
        }
    }

    // -----------------------------
    // URL helpers
    // -----------------------------
    get siteBaseUrl() {
        try {
            const raw = this.labels.siteUrl;
            const sourceUrl = raw ? new URL(raw) : new URL(window.location.href);
            const origin = sourceUrl.origin;
            const segments = (sourceUrl.pathname || '').split('/').filter((seg) => !!seg);
            const communitySegment = segments.length ? `/${segments[0]}` : '';
            return `${origin}${communitySegment}`;
        } catch (e) {
            const loc = window.location;
            const segs = (loc.pathname || '').split('/').filter((seg) => !!seg);
            const communitySegment = segs.length ? `/${segs[0]}` : '';
            return `${loc.origin}${communitySegment}`;
        }
    }

    resolveImageUrl(rel) {
        if (!rel) return null;
        if (rel.startsWith('http://') || rel.startsWith('https://')) return rel;
        const base = this.siteBaseUrl;
        const normalized = rel.startsWith('/') ? rel : `/${rel}`;
        return `${base}${normalized}`;
    }

    connectedCallback() {
        this.ensureInitialLoad();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (!pageRef) return;
        const idFromUrl = (pageRef.state && (pageRef.state.id || pageRef.state.c__id));
        if (idFromUrl && idFromUrl !== this.leadId) {
            // eslint-disable-next-line @lwc/lwc/no-api-reassignments
            this.leadId = idFromUrl;
        }
        this.ensureInitialLoad();
    }

    renderedCallback() {
        this.ensureInitialLoad();
    }

    ensureInitialLoad() {
        if (this.hasInitLoaded) return;
        if (!this.leadId) return;
        this.loadInitialData();
    }

    loadInitialData() {
        if (this.hasInitLoaded || !this.leadId) return;

        this.isInitLoading = true;
        this.hasInitLoaded = true;

        Promise.all([
            getMasterData(),
            fetchLeadForAutoRequest({ leadId: this.leadId }),
            fetchExistingRequest({ leadId: this.leadId })
        ])
            .then(([res, leadRec, existing]) => {
                this.allProjectTypes = res.projectTypes || [];
                this.allCategories = res.categories || [];
                this.allRooms = res.rooms || [];
                this.allDesigns = res.designs || [];
                this.allPlanLevels = res.designLevels || [];

                if (leadRec) this.applyLeadDefaults(leadRec);
                if (existing) this.applyExistingRequest(existing);

                if (this.selectedCategoryId && this.AUTO_DEFAULT_ROOMS && Object.keys(this.roomQuantities).length === 0) {
                    this.applyDefaultRoomsForCategory(this.selectedCategoryId);
                }
            })
            .catch((err) => {
                this.showToast('Error', this.errMsg(err, 'Unable to load project data.'), 'error');
            })
            .finally(() => {
                this.isInitLoading = false;
            });
    }

    errMsg(err, fallback) {
        return err && err.body && err.body.message ? err.body.message : fallback;
    }

    applyLeadDefaults(leadRec) {
        this.firstName = leadRec.FirstName || '';
        this.lastName = leadRec.LastName || '';
        this.email = leadRec.Email || '';
        this.phone = leadRec.Phone || '';
        this.company = leadRec.Company || '';
        this.address = leadRec.Site_Location__c || '';
        this.siteSpace = leadRec.Site_Space__c || '';
        this.description = leadRec.Project_Description__c || '';
        this.totalBudget = leadRec.Estimated_Budget__c || 0;

        this.selectedProjectTypeId = leadRec.Interior_Project_Type__c || null;
        this.selectedCategoryId = leadRec.Interior_Category__c || null;

        if (!this.quotationType && leadRec.Project_Request_Quotation_Type__c) {
            this.quotationType = leadRec.Project_Request_Quotation_Type__c;
        }

         // ✅ compute label for display (safe even if picklist wire loads later)
        if (this.quotationType) {
            this.quotationTypeLabel = this.quotationTypeLabelByValue[this.quotationType] || this.quotationType;
        }

        if (leadRec.Project_Request_Submitted__c === true) {
            this.isAlreadySubmitted = true;
        }
    }

    applyExistingRequest(existing) {
        const qtyMap = {};
        (existing.rooms || []).forEach((r) => {
            if (r.roomId && r.quantity && r.quantity > 0) qtyMap[r.roomId] = r.quantity;
        });
        this.roomQuantities = qtyMap;

        const nextIndexByRoom = {};
        const getNextIndex = (roomId) => {
            const cur = nextIndexByRoom[roomId] || 0;
            const next = cur + 1;
            nextIndexByRoom[roomId] = next;
            return next;
        };

        const designMap = {};
        const planMap = {};
        const sizeMap = {};
        let total = 0;

        (existing.roomDesigns || []).forEach((line) => {
            if (!line.roomId || !line.designId) return;

            const design = (this.allDesigns || []).find((d) => d.id === line.designId);
            const qty = line.quantity && line.quantity > 0 ? line.quantity : 1;

            for (let i = 0; i < qty; i += 1) {
                const idx = getNextIndex(line.roomId);
                const instanceKey = `${line.roomId}__${idx}`;

                const templateSizeSqft = line.templateSizeSqft != null ? line.templateSizeSqft : (design ? design.templateSizeSqft : null);
                const ratePerSqft = line.ratePerSqft != null ? line.ratePerSqft : (design ? design.ratePerSqft : null);
                const roomSizeSqft = line.roomSizeSqft != null ? line.roomSizeSqft : null;
                const planLevel = line.planLevel != null ? line.planLevel : (design ? design.designLevel : null);

                const computedAmount = this.computeAmount(roomSizeSqft, templateSizeSqft, ratePerSqft, (design ? design.finalDesignPrice : null));

                designMap[instanceKey] = {
                    roomId: line.roomId,
                    instanceIndex: idx,
                    designId: line.designId,
                    designName: design ? design.name : 'Design',
                    planLevel,
                    roomSizeSqft,
                    templateSizeSqft,
                    ratePerSqft,
                    finalDesignPrice: design ? design.finalDesignPrice : null,
                    lineAmount: computedAmount,
                    imageUrl: design ? this.resolveImageUrl(design.imageUrl) : null
                };

                if (planLevel) planMap[instanceKey] = planLevel;
                if (roomSizeSqft != null) sizeMap[instanceKey] = roomSizeSqft;

                total += (computedAmount || 0);
            }
        });

        this.roomDesignMap = designMap;
        this.instancePlanMap = planMap;
        this.instanceRoomSizeMap = sizeMap;
        this.totalBudget = total;

        const instances = this.roomInstancesView;
        if (!this.currentRoomInstanceKey && instances.length) {
            this.currentRoomInstanceKey = instances[0].instanceKey;
        }
    }

    // -----------------------------
    // Steps
    // -----------------------------
    get steps() {
        const labels = ['Customer', 'Project Type', 'Category', 'Rooms', 'Plan', 'Room Designs', 'Preview Designs', 'Review', 'Success'];
        return labels.map((label, index) => {
            const stepNumber = index + 1;
            let cls = 'step-item';
            if (stepNumber === this.currentStep) cls = 'step-item active';
            else if (stepNumber < this.currentStep) cls = 'step-item done';
            return { number: stepNumber, label, cls };
        });
    }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get isStep6() { return this.currentStep === 6; }
    get isStep7() { return this.currentStep === 7; }
    get isStep8() { return this.currentStep === 8; }
    get isStep9() { return this.currentStep === 9; }
    get displayStep() { return this.currentStep > 9 ? 9 : this.currentStep; }

    get nextLabel() {
        return this.currentStep === 8 ? (this.isSaving ? 'Saving…' : 'Save') : 'Next';
    }

    // -----------------------------
    // UI options
    // -----------------------------
    get projectTypeOptions() {
        return (this.allProjectTypes || []).map((pt) => ({
            label: pt.name,
            value: pt.id,
            cardClass: pt.id === this.selectedProjectTypeId ? 'choice-card selected' : 'choice-card'
        }));
    }

    get categoryCards() {
        return (this.allCategories || [])
            .filter((c) => c.projectTypeId === this.selectedProjectTypeId)
            .map((c) => ({
                label: c.name,
                value: c.id,
                cardClass: c.id === this.selectedCategoryId ? 'choice-card selected' : 'choice-card'
            }));
    }

    get roomsWithQty() {
        return (this.allRooms || [])
            .filter((r) => r.categoryId === this.selectedCategoryId)
            .map((r) => ({
                ...r,
                quantity: this.roomQuantities[r.id] || 0
            }));
    }

    get planOptions() {
        const chosenInstance = this.currentRoomInstanceKey;
        const selectedPlan = chosenInstance ? this.instancePlanMap[chosenInstance] : null;

        return (this.allPlanLevels || []).map((lvl) => ({
            label: lvl,
            value: lvl,
            cardClass: lvl === selectedPlan ? 'choice-card selected' : 'choice-card'
        }));
    }

    // ✅ Instances list
    get roomInstancesView() {
        const out = [];
        const roomIds = Object.keys(this.roomQuantities || {});
        roomIds.forEach((roomId) => {
            const qty = this.roomQuantities[roomId] || 0;
            if (qty <= 0) return;

            const room = this.allRooms.find((x) => x.id === roomId);
            const roomName = room ? room.name : roomId;

            for (let i = 1; i <= qty; i += 1) {
                const instanceKey = `${roomId}__${i}`;
                const rd = this.roomDesignMap[instanceKey];

                const planLabel = this.instancePlanMap[instanceKey] || 'Not selected';
                const selectedDesignName = rd ? rd.designName : 'No design selected';

                out.push({
                    instanceKey,
                    roomId,
                    instanceIndex: i,
                    displayName: qty > 1 ? `${roomName} (${i}/${qty})` : roomName,
                    planLabel,
                    selectedDesignName,
                    cardClass: instanceKey === this.currentRoomInstanceKey ? 'room-sel-card active' : 'room-sel-card'
                });
            }
        });

        if (!this.currentRoomInstanceKey && out.length) this.currentRoomInstanceKey = out[0].instanceKey;
        return out;
    }

    parseInstanceKey(instanceKey) {
        const parts = (instanceKey || '').split('__');
        return { roomId: parts[0], instanceIndex: parts.length > 1 ? parseInt(parts[1], 10) : 1 };
    }

    // ✅ filter designs by room + instance plan
    get currentRoomDesigns() {
        if (!this.currentRoomInstanceKey) return [];

        const { roomId } = this.parseInstanceKey(this.currentRoomInstanceKey);
        const plan = this.instancePlanMap[this.currentRoomInstanceKey];
        const selectedForInstance = this.roomDesignMap[this.currentRoomInstanceKey];

        const placeholder = 'https://via.placeholder.com/220x140?text=Design';

        return (this.allDesigns || [])
            .filter((d) => d.roomId === roomId && (!plan || d.designLevel === plan))
            .map((d) => {
                const fullUrl = this.resolveImageUrl(d.imageUrl);
                const isSelected = selectedForInstance && selectedForInstance.designId === d.id;
                return {
                    ...d,
                    itemClass: isSelected ? 'design-item-tile selected' : 'design-item-tile',
                    thumbUrl: fullUrl || placeholder,
                    fullImageUrl: fullUrl || placeholder
                };
            });
    }

    // -----------------------------
    // Display helpers
    // -----------------------------
    fmtSqft(v) {
        return v != null && v !== '' && !Number.isNaN(Number(v)) ? `${Number(v)} sqft` : '-';
    }

    fmtRate(v) {
        return v != null && v !== '' && !Number.isNaN(Number(v)) ? `${Number(v)} /sqft` : '-';
    }

    fmtApproxCurrency(v) {
        const n = v != null && !Number.isNaN(Number(v)) ? Number(v) : 0;
        return `Approximate: ${n.toFixed(2)}`;
    }

    get currentRoomSize() {
        if (!this.currentRoomInstanceKey) return null;
        return this.instanceRoomSizeMap[this.currentRoomInstanceKey] ?? null;
    }

    get currentTemplateSizeDisplay() {
        const rd = this.roomDesignMap[this.currentRoomInstanceKey];
        return rd ? this.fmtSqft(rd.templateSizeSqft) : '-';
    }

    get currentRatePerSqftDisplay() {
        const rd = this.roomDesignMap[this.currentRoomInstanceKey];
        return rd ? this.fmtRate(rd.ratePerSqft) : '-';
    }

    get currentLineAmountDisplay() {
        const rd = this.roomDesignMap[this.currentRoomInstanceKey];
        return rd && rd.lineAmount != null ? this.fmtApproxCurrency(rd.lineAmount) : 'Approximate: 0.00';
    }

    // ✅ Preview tiles in correct order (instances order)
    get selectedDesignTiles() {
        const out = [];
        (this.roomInstancesView || []).forEach((inst) => {
            const rd = this.roomDesignMap[inst.instanceKey];
            if (!rd) return;

            out.push({
                instanceKey: inst.instanceKey,
                roomName: inst.displayName,
                designName: rd.designName,
                planLevel: rd.planLevel || this.instancePlanMap[inst.instanceKey] || '-',
                roomSizeText: this.fmtSqft(rd.roomSizeSqft),
                templateSizeText: this.fmtSqft(rd.templateSizeSqft),
                rateText: this.fmtRate(rd.ratePerSqft),
                lineAmount: rd.lineAmount || 0
            });
        });
        return out;
    }

    get reviewRows() {
        return (this.selectedDesignTiles || []).map((t) => ({
            key: t.instanceKey,
            room: `${t.roomName} → ${t.designName}`,
            plan: t.planLevel || '-',
            roomSize: t.roomSizeText,
            template: t.templateSizeText,
            rate: t.rateText,
            amount: t.lineAmount
        }));
    }

    get selectedProjectTypeName() {
        const pt = (this.allProjectTypes || []).find((x) => x.id === this.selectedProjectTypeId);
        return pt ? pt.name : '';
    }

    get selectedCategoryName() {
        const cat = (this.allCategories || []).find((x) => x.id === this.selectedCategoryId);
        return cat ? cat.name : '';
    }

    // -----------------------------
    // Computation
    // -----------------------------
    computeAmount(roomSizeSqft, templateSizeSqft, ratePerSqft, finalDesignPrice) {
        const rate = ratePerSqft != null ? Number(ratePerSqft) : null;

        if (rate != null && !Number.isNaN(rate)) {
            const roomSize = roomSizeSqft != null && roomSizeSqft !== '' ? Number(roomSizeSqft) : null;
            if (roomSize != null && !Number.isNaN(roomSize) && roomSize > 0) return roomSize * rate;

            const tmpl = templateSizeSqft != null ? Number(templateSizeSqft) : null;
            if (tmpl != null && !Number.isNaN(tmpl) && tmpl > 0) return tmpl * rate;
        }

        const fp = finalDesignPrice != null ? Number(finalDesignPrice) : null;
        return fp != null && !Number.isNaN(fp) ? fp : 0;
    }

    recalcTotal() {
        let total = 0;
        Object.keys(this.roomDesignMap || {}).forEach((k) => {
            total += (this.roomDesignMap[k].lineAmount || 0);
        });
        this.totalBudget = total;
    }

    // -----------------------------
    // Defaults
    // -----------------------------
    applyDefaultRoomsForCategory(categoryId) {
        const qtyMap = {};
        (this.allRooms || []).filter((r) => r.categoryId === categoryId).forEach((r) => {
            qtyMap[r.id] = 1;
        });
        this.roomQuantities = qtyMap;

        this.roomDesignMap = {};
        this.instancePlanMap = {};
        this.instanceRoomSizeMap = {};
        this.currentRoomInstanceKey = null;
        this.totalBudget = 0;
    }

    // -----------------------------
    // Handlers
    // -----------------------------
    handleInput(event) {
        const fld = event.target.dataset.field;
        this[fld] = event.target.value;
    }

    handleProjectTypeCardClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedProjectTypeId = id;

        this.selectedCategoryId = null;
        this.roomQuantities = {};
        this.roomDesignMap = {};
        this.instancePlanMap = {};
        this.instanceRoomSizeMap = {};
        this.currentRoomInstanceKey = null;
        this.totalBudget = 0;
    }

    handleCategoryCardClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCategoryId = id;

        this.roomDesignMap = {};
        this.instancePlanMap = {};
        this.instanceRoomSizeMap = {};
        this.currentRoomInstanceKey = null;
        this.totalBudget = 0;

        if (this.AUTO_DEFAULT_ROOMS) this.applyDefaultRoomsForCategory(id);
    }

    handleRoomIncrement(event) {
        const id = event.currentTarget.dataset.id;
        const cur = this.roomQuantities[id] || 0;
        this.roomQuantities = { ...this.roomQuantities, [id]: cur + 1 };
    }

    handleRoomDecrement(event) {
        const id = event.currentTarget.dataset.id;
        const cur = this.roomQuantities[id] || 0;
        const nextQty = Math.max(cur - 1, 0);
        this.roomQuantities = { ...this.roomQuantities, [id]: nextQty };

        const cleanedDesignMap = { ...this.roomDesignMap };
        const cleanedPlanMap = { ...this.instancePlanMap };
        const cleanedSizeMap = { ...this.instanceRoomSizeMap };

        Object.keys(cleanedDesignMap).forEach((instanceKey) => {
            const { roomId, instanceIndex } = this.parseInstanceKey(instanceKey);
            const max = this.roomQuantities[roomId] || 0;
            if (instanceIndex > max) delete cleanedDesignMap[instanceKey];
        });
        Object.keys(cleanedPlanMap).forEach((instanceKey) => {
            const { roomId, instanceIndex } = this.parseInstanceKey(instanceKey);
            const max = this.roomQuantities[roomId] || 0;
            if (instanceIndex > max) delete cleanedPlanMap[instanceKey];
        });
        Object.keys(cleanedSizeMap).forEach((instanceKey) => {
            const { roomId, instanceIndex } = this.parseInstanceKey(instanceKey);
            const max = this.roomQuantities[roomId] || 0;
            if (instanceIndex > max) delete cleanedSizeMap[instanceKey];
        });

        this.roomDesignMap = cleanedDesignMap;
        this.instancePlanMap = cleanedPlanMap;
        this.instanceRoomSizeMap = cleanedSizeMap;

        this.recalcTotal();
    }

    // Step 5
    handleRoomSelectForPlan(event) {
        this.currentRoomInstanceKey = event.currentTarget.dataset.id;
    }

    resetInstanceDesign(instanceKey, { clearRoomSize = false } = {}) {
        if (!instanceKey) return;

        // remove selected design for this instance
        const designClone = { ...this.roomDesignMap };
        if (designClone[instanceKey]) {
            delete designClone[instanceKey];
            this.roomDesignMap = designClone;
        }

        // optional: clear room size too (if you want full reset)
        if (clearRoomSize) {
            const sizeClone = { ...this.instanceRoomSizeMap };
            if (sizeClone[instanceKey] !== undefined) {
                delete sizeClone[instanceKey];
                this.instanceRoomSizeMap = sizeClone;
            }
        }

        this.recalcTotal();
    }

    handlePlanSelectForInstance(event) {
        const plan = event.currentTarget.dataset.id;
        if (!this.currentRoomInstanceKey || !plan) return;

        const instanceKey = this.currentRoomInstanceKey;
        const prevPlan = this.instancePlanMap[instanceKey];

        // ✅ Update plan selection
        this.instancePlanMap = { ...this.instancePlanMap, [instanceKey]: plan };

        // ✅ If plan changed, clear old design so user must re-pick
        if (prevPlan !== plan) {
            this.resetInstanceDesign(instanceKey, { clearRoomSize: false }); // set true if you want to clear sqft also
        }
    }

    // Step 6
    handleRoomSelectForDesign(event) {
        this.currentRoomInstanceKey = event.currentTarget.dataset.id;
    }

    handleRoomSizeChange(event) {
        if (!this.currentRoomInstanceKey) return;
        const val = event.target.value;
        const num = val === '' || val == null ? null : Number(val);

        this.instanceRoomSizeMap = { ...this.instanceRoomSizeMap, [this.currentRoomInstanceKey]: num };

        const rd = this.roomDesignMap[this.currentRoomInstanceKey];
        if (rd) {
            const newAmount = this.computeAmount(num, rd.templateSizeSqft, rd.ratePerSqft, rd.finalDesignPrice);
            this.roomDesignMap = { ...this.roomDesignMap, [this.currentRoomInstanceKey]: { ...rd, roomSizeSqft: num, lineAmount: newAmount } };
            this.recalcTotal();
        }
    }

    handleRoomDesignPick(event) {
        const designId = event.currentTarget.dataset.id;
        if (!designId || !this.currentRoomInstanceKey) return;

        const design = (this.allDesigns || []).find((x) => x.id === designId);
        if (!design) return;

        const { roomId, instanceIndex } = this.parseInstanceKey(this.currentRoomInstanceKey);

        const planLevel = this.instancePlanMap[this.currentRoomInstanceKey] || design.designLevel || null;
        const roomSizeSqft = this.instanceRoomSizeMap[this.currentRoomInstanceKey] ?? null;

        const templateSizeSqft = design.templateSizeSqft ?? null;
        const ratePerSqft = design.ratePerSqft ?? null;

        const amount = this.computeAmount(roomSizeSqft, templateSizeSqft, ratePerSqft, design.finalDesignPrice);

        this.roomDesignMap = {
            ...this.roomDesignMap,
            [this.currentRoomInstanceKey]: {
                roomId,
                instanceIndex,
                designId: design.id,
                designName: design.name,
                planLevel,
                roomSizeSqft,
                templateSizeSqft,
                ratePerSqft,
                finalDesignPrice: design.finalDesignPrice,
                lineAmount: amount,
                imageUrl: this.resolveImageUrl(design.imageUrl)
            }
        };

        if (planLevel) {
            this.instancePlanMap = { ...this.instancePlanMap, [this.currentRoomInstanceKey]: planLevel };
        }

        this.recalcTotal();
    }

    handleRemoveSelected(event) {
        const instanceKey = event.currentTarget.dataset.instancekey;
        const cloned = { ...this.roomDesignMap };
        delete cloned[instanceKey];
        this.roomDesignMap = cloned;
        this.recalcTotal();
    }

    openImageModal(event) {
        event.stopPropagation();
        this.modalImageUrl = event.currentTarget.dataset.img;
        this.modalTitle = event.currentTarget.dataset.title;
        this.isImageModalOpen = true;
    }

    closeImageModal() {
        this.isImageModalOpen = false;
        this.modalImageUrl = null;
        this.modalTitle = null;
    }

    // -----------------------------
    // Next/Prev + validation
    // -----------------------------
    handleNext() {
        if (this.isAlreadySubmitted || this.isSaving) return;

        if (this.currentStep === 1) {
            if (!this.firstName || !this.lastName || !this.email || !this.phone || !this.siteSpace) {
                this.showToast('Missing info', 'First Name, Last Name, Email, Phone and Site Space are required.', 'error');
                return;
            }
        }
        if (this.currentStep === 2 && !this.selectedProjectTypeId) {
            this.showToast('Select project type', 'Please select a project type.', 'error');
            return;
        }
        if (this.currentStep === 3 && !this.selectedCategoryId) {
            this.showToast('Select category', 'Please select a category.', 'error');
            return;
        }
        if (this.currentStep === 4) {
            const hasRoom = Object.values(this.roomQuantities || {}).some((q) => q > 0);
            if (!hasRoom) {
                this.showToast('Select rooms', 'Please add at least one room.', 'error');
                return;
            }
        }

        // Step 5: require plan for each instance
        if (this.currentStep === 5) {
            const missingPlan = (this.roomInstancesView || []).some((inst) => !this.instancePlanMap[inst.instanceKey]);
            if (missingPlan) {
                this.showToast('Plan missing', 'Please select plan for every room (including each quantity item).', 'error');
                return;
            }
        }

        // Step 6: require design for each instance
        if (this.currentStep === 6) {
            const missingDesign = (this.roomInstancesView || []).some((inst) => !this.roomDesignMap[inst.instanceKey]);
            if (missingDesign) {
                this.showToast('Designs missing', 'Please choose a design for every room item.', 'error');
                return;
            }
            this.recalcTotal();
        }

        if (this.currentStep === 7) {
            const missingDesign = (this.roomInstancesView || []).some((inst) => !this.roomDesignMap[inst.instanceKey]);
            if (missingDesign) {
                this.showToast('Design removed', 'Please ensure every room item has a design.', 'error');
                this.currentStep = 6;
                return;
            }
        }

        if (this.currentStep < 8) this.currentStep += 1;
        else if (this.currentStep === 8) this.saveData();
    }

    handlePrev() {
        if (this.isAlreadySubmitted) {
            this.handleAlreadySubmittedClose();
            return;
        }
        if (this.currentStep === 1) {
            this.dispatchEvent(new CustomEvent('previous'));
            return;
        }
        this.currentStep -= 1;
    }

    // -----------------------------
    // Save
    // -----------------------------
    saveData() {
        this.isSaving = true;

        const rooms = [];
        Object.keys(this.roomQuantities || {}).forEach((roomId) => {
            const qty = this.roomQuantities[roomId];
            if (qty && qty > 0) rooms.push({ roomId, quantity: qty });
        });

        const selectedRoomDesigns = [];
        Object.keys(this.roomDesignMap || {}).forEach((instanceKey) => {
            const rd = this.roomDesignMap[instanceKey];
            selectedRoomDesigns.push({
                roomId: rd.roomId,
                designId: rd.designId,
                quantity: 1,
                lineAmount: rd.lineAmount,

                planLevel: rd.planLevel,
                roomSizeSqft: rd.roomSizeSqft,
                templateSizeSqft: rd.templateSizeSqft,
                ratePerSqft: rd.ratePerSqft
            });
        });

        // Store Lead.Plan_Level__c as first instance plan (optional)
        const firstInstance = (this.roomInstancesView || [])[0];
        const anyPlan = firstInstance ? (this.instancePlanMap[firstInstance.instanceKey] || null) : null;

        const payload = {
            leadId: this.leadId,
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            company: this.company,
            address: this.address,
            siteSpace: this.siteSpace,
            description: this.description,
            projectTypeId: this.selectedProjectTypeId,
            categoryId: this.selectedCategoryId,
            planLevel: anyPlan,
            rooms,
            selectedRoomDesigns,
            totalBudget: this.totalBudget,
            quotationType: this.quotationType
        };

        saveRequest({ req: payload })
            .then(() => {
                this.isSaving = false;
                this.currentStep = 9;
            })
            .catch((err) => {
                this.isSaving = false;
                this.showToast('Error', this.errMsg(err, 'Unable to submit project request.'), 'error');
            });
    }

    // -----------------------------
    // Toast + close
    // -----------------------------
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleClose() {
        if (this.labels.siteUrl) window.location.href = this.labels.siteUrl;
    }
    handleAlreadySubmittedClose() {
        if (this.labels.siteUrl) window.location.href = this.labels.siteUrl;
    }
}