import Constants from '../common/Constants'
import { DraftOwner, DraftService, MailDraft } from '../common/DraftService'
import { DateTimeUtils } from '../common/DateTimeUtils'
import { DraftListDataSource } from '../common/DraftListDataSource'
import { EmptyState } from '../components/EmptyState'
import { ComposeParams } from './ComposePage'

@Component
export struct DraftsPage {
  scroller: Scroller = new Scroller()
  @Prop topContentInset: number = Constants.TITLE_BAR_HEIGHT_MINI
  private dataSource: DraftListDataSource = new DraftListDataSource()
  private pathStack: NavPathStack = AppStorage.get('appPathStack') as NavPathStack
  @StorageLink('draftRevision') @Watch('onDraftRevision') draftRevision: number = 0
  @StorageLink('sessionRevision') @Watch('onDraftRevision') sessionRevision: number = 0
  @StorageLink('draftStorageError') draftStorageError: boolean = false
  @State draftList: MailDraft[] = []
  @State unassignedCount: number = 0

  aboutToAppear(): void {
    this.refreshDrafts()
  }

  private onDraftRevision(): void {
    this.refreshDrafts()
  }

  private refreshDrafts(): void {
    this.draftList = DraftService.getDrafts()
    this.unassignedCount = DraftService.getUnassignedCount()
    this.dataSource.setData(this.draftList)
  }

  private deleteDraft(id: number): void {
    try {
      DraftService.deleteDraft(id)
      this.refreshDrafts()
    } catch (err) {
      this.getUIContext().getPromptAction().openToast({ message: this.resourceText($r('app.string.draft_delete_failed')) })
    }
  }

  private editDraft(item: MailDraft): void {
    const params: ComposeParams = new ComposeParams(item.toEmail, item.ccEmail, item.bccEmail, item.subject, item.content,
      item.sendType, item.emailId, item.id)
    params.instanceId = item.instanceId
    params.ownerEmail = item.ownerEmail
    params.senderAccountId = item.senderAccountId
    this.pathStack.pushPathByName('ComposePage', params)
  }

  private resourceText(resource: Resource): string {
    const context: Context = this.getUIContext().getHostContext() as Context
    return context.resourceManager.getStringSync(resource.id)
  }

  private async importLegacyDrafts(): Promise<void> {
    const owner: DraftOwner = DraftService.captureOwner()
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.draft_import_title'),
        message: $r('app.string.draft_import_message', owner.email,
          (AppStorage.get('activeInstanceName') as string | undefined) || owner.instanceId),
        buttons: [
          { text: $r('app.string.draft_cancel'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.draft_import_confirm'), color: $r('app.color.primary') }
        ]
      })
      if (result.index !== 1) { return }
      DraftService.importUnassigned(owner)
    } catch (err) {
      this.getUIContext().getPromptAction().openToast({ message: this.resourceText($r('app.string.draft_import_failed')) })
    } finally {
      this.refreshDrafts()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.draftList.length === 0 && this.unassignedCount === 0 && !this.draftStorageError) {
        Column() {
          EmptyState({ icon: $r('sys.symbol.doc'), message: '暂无草稿' })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topContentInset })
      } else {
        List({ scroller: this.scroller }) {
          ListItem() {
            Column().height(this.topContentInset)
          }
          if (this.draftStorageError) {
            ListItem() {
              Text($r('app.string.draft_storage_unavailable'))
                .fontSize(Constants.FONT_SIZE_SMALL)
                .fontColor($r('app.color.danger'))
                .padding(Constants.PADDING_INNER)
            }
          }
          if (this.unassignedCount > 0) {
            ListItem() {
              Column({ space: 8 }) {
                Text($r('app.string.draft_legacy_notice', this.unassignedCount))
                  .fontSize(Constants.FONT_SIZE_SMALL)
                  .fontColor($r('app.color.text_secondary'))
                Button($r('app.string.draft_import_title'))
                  .enabled(!this.draftStorageError)
                  .onClick(() => { this.importLegacyDrafts() })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(Constants.PADDING_INNER)
              .backgroundColor($r('app.color.card'))
              .borderRadius(Constants.RADIUS_CARD)
              .margin({ top: 4, bottom: 8 })
            }
          }
          LazyForEach(this.dataSource, (item: MailDraft) => {
            ListItem() {
              Row() {
                Column() {
                  Row() {
                    Text(item.subject === '' ? '无主题' : item.subject)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text(DateTimeUtils.formatUtcDateTime(item.time))
                      .fontSize(12)
                      .fontColor($r('app.color.text_tertiary'))
                  }
                  .width('100%')

                  Text('收件人: ' + (item.toEmail === '' ? '未填写' : item.toEmail))
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ top: 14, bottom: 14, left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
              .borderRadius(Constants.RADIUS_CARD)
              .backgroundColor($r('app.color.card'))
              .margin({ top: 4, bottom: 4 })
              .onClick(() => { this.editDraft(item) })
            }
            .swipeAction({
              end: {
                builder: () => { this.DeleteDraftAction(item.id) },
                actionAreaDistance: 80
              },
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (item: MailDraft): string => item.id.toString())
          ListItem() {
            Column().height(Constants.PADDING_TAB_CONTENT_BOTTOM)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .padding({ left: Constants.PADDING_EDGE, right: Constants.PADDING_EDGE })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder DeleteDraftAction(id: number) {
    Row() {
      Button() {
        Column() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([Color.White])
          Text('删除')
            .fontSize(12)
            .fontColor(Color.White)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width(80)
      .height('100%')
      .backgroundColor($r('app.color.danger'))
      .onClick(() => { this.deleteDraft(id) })
    }
    .height('100%')
  }
}
