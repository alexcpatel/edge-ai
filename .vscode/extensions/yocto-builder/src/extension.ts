import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

interface InstanceStatus {
    id: string;
    type: string;
    state: string;
    ip?: string;
    healthy?: boolean;
}

interface BuildStatus {
    running: boolean;
    elapsed?: string;
    errors?: string[];
    warning?: string;
}

export function activate(context: vscode.ExtensionContext) {
    const outputChannel = vscode.window.createOutputChannel('Yocto Builder');
    outputChannel.appendLine('Yocto Builder extension activated');
    outputChannel.show();

    let provider: YoctoBuilderProvider | undefined;

    try {
        provider = new YoctoBuilderProvider(context.extensionPath);
        const treeView = vscode.window.createTreeView('yocto-builder', {
            treeDataProvider: provider,
            showCollapseAll: false
        });

        // Register commands first
        context.subscriptions.push(
            vscode.commands.registerCommand('yocto-builder.showPanel', () => {
                outputChannel.appendLine('Command: showPanel');
                YoctoBuilderPanel.createOrShow(context.extensionPath, context);
            }),
            vscode.commands.registerCommand('yocto-builder.instanceStart', () => {
                outputChannel.appendLine('Command: instanceStart');
                runCommand('make instance-start');
            }),
            vscode.commands.registerCommand('yocto-builder.instanceStop', () => {
                outputChannel.appendLine('Command: instanceStop');
                runCommand('make instance-stop');
            }),
            vscode.commands.registerCommand('yocto-builder.instanceSsh', () => {
                outputChannel.appendLine('Command: instanceSsh');
                runCommand('make instance-ssh', 'Yocto Builder - SSH');
            }),
            vscode.commands.registerCommand('yocto-builder.instanceHealth', () => {
                outputChannel.appendLine('Command: instanceHealth');
                runCommand('make instance-health', 'Yocto Builder - Health');
            }),
            vscode.commands.registerCommand('yocto-builder.buildStart', () => {
                outputChannel.appendLine('Command: buildStart');
                runCommand('make build-image', 'Yocto Builder - Build');
            }),
            vscode.commands.registerCommand('yocto-builder.buildWatch', () => {
                outputChannel.appendLine('Command: buildWatch');
                runCommand('make build-watch', 'Yocto Builder - Watch');
            }),
            vscode.commands.registerCommand('yocto-builder.buildTerminate', () => {
                outputChannel.appendLine('Command: buildTerminate');
                runCommand('make build-terminate', 'Yocto Builder - Terminate');
            }),
            vscode.commands.registerCommand('yocto-builder.refresh', () => {
                outputChannel.appendLine('Command: refresh');
                provider?.refresh();
                YoctoBuilderPanel.currentPanel?.update();
            })
        );

        outputChannel.appendLine('Commands registered');

        // Auto-open panel on activation (only if workspace is available)
        if (vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders.length > 0) {
            outputChannel.appendLine('Workspace found, opening panel');
            YoctoBuilderPanel.createOrShow(context.extensionPath, context);
        } else {
            outputChannel.appendLine('No workspace found');
            // Show message to open workspace
            vscode.window.showInformationMessage(
                'Yocto Builder: Please open a workspace folder to use this extension',
                'Open Folder'
            ).then(selection => {
                if (selection === 'Open Folder') {
                    vscode.commands.executeCommand('workbench.action.files.openFolder');
                }
            });
        }
    } catch (error) {
        outputChannel.appendLine(`Error during activation: ${error}`);
        vscode.window.showErrorMessage(`Yocto Builder activation error: ${error}`);
    }

    // Auto-refresh every 5 seconds
    const refreshInterval = setInterval(() => {
        provider?.refresh();
        YoctoBuilderPanel.currentPanel?.update();
    }, 5000);

    context.subscriptions.push({
        dispose: () => clearInterval(refreshInterval)
    });
}

async function runCommand(command: string, terminalName?: string): Promise<void> {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
        vscode.window.showErrorMessage('No workspace folder found');
        return;
    }

    const name = terminalName || 'Yocto Builder';
    const terminal = vscode.window.createTerminal(name);
    terminal.show(true); // Show and focus the terminal
    terminal.sendText(`cd ${workspaceFolder.uri.fsPath} && ${command}`);
}

class YoctoBuilderProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
    private _onDidChangeTreeData: vscode.EventEmitter<vscode.TreeItem | undefined | null | void> = new vscode.EventEmitter<vscode.TreeItem | undefined | null | void>();
    readonly onDidChangeTreeData: vscode.Event<vscode.TreeItem | undefined | null | void> = this._onDidChangeTreeData.event;

    constructor(private extensionPath: string) { }

    refresh(): void {
        this._onDidChangeTreeData.fire();
    }

    getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
        return element;
    }

    async getChildren(element?: vscode.TreeItem): Promise<vscode.TreeItem[]> {
        if (!element) {
            return [
                new StatusItem('Instance Status', 'instance-status'),
                new StatusItem('Build Status', 'build-status')
            ];
        }
        return [];
    }
}

class StatusItem extends vscode.TreeItem {
    constructor(
        public readonly label: string,
        public readonly type: string
    ) {
        super(label, vscode.TreeItemCollapsibleState.None);
        this.command = {
            command: 'yocto-builder.showPanel',
            title: 'Show Status'
        };
    }
}

class YoctoBuilderPanel {
    public static currentPanel: YoctoBuilderPanel | undefined;
    private readonly _panel: vscode.WebviewPanel;
    private readonly _extensionPath: string;
    private readonly _context: vscode.ExtensionContext;
    private _disposables: vscode.Disposable[] = [];
    private _previousBuildRunning: boolean = false;

    public static createOrShow(extensionPath: string, context: vscode.ExtensionContext) {
        const column = vscode.window.activeTextEditor
            ? vscode.window.activeTextEditor.viewColumn
            : undefined;

        if (YoctoBuilderPanel.currentPanel) {
            YoctoBuilderPanel.currentPanel._panel.reveal(column);
            return;
        }

        const panel = vscode.window.createWebviewPanel(
            'yoctoBuilder',
            'Yocto Builder',
            column || vscode.ViewColumn.One,
            {
                enableScripts: true,
                localResourceRoots: [vscode.Uri.file(path.join(extensionPath, 'media'))]
            }
        );

        YoctoBuilderPanel.currentPanel = new YoctoBuilderPanel(panel, extensionPath, context);
    }

    private constructor(panel: vscode.WebviewPanel, extensionPath: string, context: vscode.ExtensionContext) {
        this._panel = panel;
        this._extensionPath = extensionPath;
        this._context = context;

        this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
        this._panel.webview.onDidReceiveMessage(
            async message => {
                switch (message.command) {
                    case 'instanceStart':
                        runCommand('make instance-start', 'Yocto Builder - Start');
                        // Sync auto-stop preference to server after instance starts (silently, no terminal)
                        const autoStopPref = this._context.globalState.get<boolean>('autoStopOnBuildComplete', false);
                        if (autoStopPref) {
                            const wsFolder = vscode.workspace.workspaceFolders?.[0];
                            if (wsFolder) {
                                setTimeout(async () => {
                                    try {
                                        const instanceStatus = await this.getInstanceStatus(wsFolder.uri.fsPath);
                                        if (instanceStatus.state?.toLowerCase() === 'running') {
                                            // Run silently without opening a terminal
                                            await execAsync('make build-set-auto-stop', { cwd: wsFolder.uri.fsPath });
                                        }
                                    } catch (error) {
                                        // Ignore errors
                                    }
                                }, 5000); // Wait 5 seconds for instance to be ready
                            }
                        }
                        break;
                    case 'instanceStop':
                        await this.handleInstanceStop();
                        break;
                    case 'instanceSsh':
                        runCommand('make instance-ssh', 'Yocto Builder - SSH');
                        break;
                    case 'instanceHealth':
                        runCommand('make instance-health', 'Yocto Builder - Health');
                        break;
                    case 'buildStart':
                        runCommand('make build-image', 'Yocto Builder - Build');
                        // Sync auto-stop preference to server after instance starts (silently, no terminal)
                        const autoStopPreference = this._context.globalState.get<boolean>('autoStopOnBuildComplete', false);
                        if (autoStopPreference) {
                            const wsFolder = vscode.workspace.workspaceFolders?.[0];
                            if (wsFolder) {
                                // Wait a bit for instance to start, then sync preference silently
                                setTimeout(async () => {
                                    try {
                                        const instanceStatus = await this.getInstanceStatus(wsFolder.uri.fsPath);
                                        if (instanceStatus.state?.toLowerCase() === 'running') {
                                            // Run silently without opening a terminal
                                            await execAsync('make build-set-auto-stop', { cwd: wsFolder.uri.fsPath });
                                        }
                                    } catch (error) {
                                        // Ignore errors
                                    }
                                }, 10000); // Wait 10 seconds for instance to be ready
                            }
                        }
                        break;
                    case 'buildWatch':
                        runCommand('make build-watch', 'Yocto Builder - Watch');
                        break;
                    case 'buildTerminate':
                        runCommand('make build-terminate', 'Yocto Builder - Terminate');
                        break;
                    case 'toggleStopOnComplete':
                        // Store preference locally (works even when instance is not running)
                        this._context.globalState.update('autoStopOnBuildComplete', message.value || false);

                        // If instance is running, sync to server immediately (silently, no terminal)
                        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
                        if (workspaceFolder) {
                            try {
                                const instanceStatus = await this.getInstanceStatus(workspaceFolder.uri.fsPath);
                                if (instanceStatus.state?.toLowerCase() === 'running') {
                                    if (message.value) {
                                        // Run silently without opening a terminal
                                        await execAsync('make build-set-auto-stop', { cwd: workspaceFolder.uri.fsPath });
                                    } else {
                                        // Run silently without opening a terminal
                                        await execAsync('make build-unset-auto-stop', { cwd: workspaceFolder.uri.fsPath });
                                    }
                                }
                            } catch (error) {
                                // Instance not running, that's okay - preference is stored locally
                            }
                        }
                        // Update UI to reflect change
                        this.update();
                        break;
                    case 'refresh':
                        this.update();
                        break;
                }
            },
            null,
            this._disposables
        );

        this.update();
    }

    public async update() {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (workspaceFolder) {
            // Track build state for UI updates
            const buildStatus = await this.getBuildStatus(workspaceFolder.uri.fsPath);
            this._previousBuildRunning = buildStatus.running;
        }

        const webview = this._panel.webview;
        this._panel.webview.html = await this._getHtmlForWebview(webview);
    }

    private async handleInstanceStop(): Promise<void> {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            vscode.window.showErrorMessage('No workspace folder found');
            return;
        }

        // Show confirmation dialog immediately (before checking build status)
        const confirm = await vscode.window.showWarningMessage(
            'Are you sure you want to stop the instance?',
            { modal: true },
            'Yes, Stop Instance',
            'Cancel'
        );

        if (confirm !== 'Yes, Stop Instance') {
            return;
        }

        // Check if build is running (after confirmation for faster UX)
        try {
            const buildStatus = await this.getBuildStatus(workspaceFolder.uri.fsPath);
            if (buildStatus.running) {
                const result = await vscode.window.showWarningMessage(
                    'A build is currently running. You must terminate the build before stopping the instance.',
                    'Terminate Build',
                    'Cancel'
                );
                if (result === 'Terminate Build') {
                    runCommand('make build-terminate');
                    // Wait a moment and check again
                    await new Promise(resolve => setTimeout(resolve, 2000));
                    const newBuildStatus = await this.getBuildStatus(workspaceFolder.uri.fsPath);
                    if (newBuildStatus.running) {
                        vscode.window.showErrorMessage('Build termination may still be in progress. Please wait and try again.');
                        return;
                    }
                } else {
                    return;
                }
            }
        } catch (error) {
            // If we can't check build status, continue
        }

        // Stop the instance
        runCommand('make instance-stop');
    }

    private async _getHtmlForWebview(webview: vscode.Webview): Promise<string> {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            return `<!DOCTYPE html>
<html>
<head><title>Yocto Builder</title></head>
<body style="padding: 20px; font-family: var(--vscode-font-family);">
    <h2>No Workspace Folder Found</h2>
    <p>Please open the workspace folder (edge-ai) in this window to use the Yocto Builder extension.</p>
    <p>Go to File > Open Folder and select the edge-ai directory.</p>
</body>
</html>`;
        }

        const instanceStatus = await this.getInstanceStatus(workspaceFolder.uri.fsPath);
        const buildStatus = await this.getBuildStatus(workspaceFolder.uri.fsPath);

        // Read HTML template
        const htmlPath = path.join(this._extensionPath, 'media', 'webview.html');
        let html = fs.readFileSync(htmlPath, 'utf8');

        // Normalize instance state for comparison
        const instanceRunning = instanceStatus.state?.toLowerCase() === 'running';

        // Replace template variables
        html = html.replace(/\{\{INSTANCE_STATUS_CLASS\}\}/g, instanceRunning ? 'running' : 'stopped');
        html = html.replace(/\{\{INSTANCE_STATE\}\}/g, instanceStatus.state || 'unknown');
        html = html.replace(/\{\{INSTANCE_ID\}\}/g, instanceStatus.id || 'N/A');
        html = html.replace(/\{\{INSTANCE_TYPE\}\}/g, instanceStatus.type || 'N/A');
        html = html.replace(/\{\{INSTANCE_IP\}\}/g, instanceStatus.ip || 'N/A');
        html = html.replace(/\{\{INSTANCE_START_DISABLED\}\}/g, instanceRunning ? 'disabled' : '');
        // Disable stop if instance is not running OR if build is running
        html = html.replace(/\{\{INSTANCE_STOP_DISABLED\}\}/g, (!instanceRunning || buildStatus.running) ? 'disabled' : '');
        // Disable SSH and Health if instance is not running
        html = html.replace(/\{\{INSTANCE_SSH_DISABLED\}\}/g, !instanceRunning ? 'disabled' : '');
        html = html.replace(/\{\{INSTANCE_HEALTH_DISABLED\}\}/g, !instanceRunning ? 'disabled' : '');

        html = html.replace(/\{\{BUILD_STATUS_CLASS\}\}/g, buildStatus.running ? 'running' : 'stopped');
        html = html.replace(/\{\{BUILD_STATUS_TEXT\}\}/g, buildStatus.running ? 'Running' : 'Not Running');
        // Disable Start Build only if build is already running (instance will auto-start via Makefile)
        html = html.replace(/\{\{BUILD_START_DISABLED\}\}/g, buildStatus.running ? 'disabled' : '');
        // Disable Watch/Terminate if build is not running
        html = html.replace(/\{\{BUILD_WATCH_DISABLED\}\}/g, !buildStatus.running ? 'disabled' : '');
        html = html.replace(/\{\{BUILD_TERMINATE_DISABLED\}\}/g, !buildStatus.running ? 'disabled' : '');

        // Stop on build complete option (always visible and selectable)
        // Check server-side flag file status if instance is running, otherwise use local preference
        let autoStopEnabled = false;
        const localPreference = this._context.globalState.get<boolean>('autoStopOnBuildComplete', false);

        if (instanceRunning) {
            try {
                const { stdout } = await execAsync('make build-check-auto-stop', { cwd: workspaceFolder.uri.fsPath });
                autoStopEnabled = stdout.includes('enabled') || stdout.trim() === '1';
                // Sync local preference if server has different value
                if (autoStopEnabled !== localPreference) {
                    this._context.globalState.update('autoStopOnBuildComplete', autoStopEnabled);
                }
            } catch (error) {
                // If command fails, use local preference
                autoStopEnabled = localPreference;
            }
        } else {
            // Instance not running, use local preference
            autoStopEnabled = localPreference;
        }

        const stopOnCompleteHtml = `
        <div class="stop-on-complete">
            <label>
                <input type="checkbox" id="stopOnComplete" ${autoStopEnabled ? 'checked' : ''} onchange="toggleStopOnComplete(this.checked)">
                Stop instance when build ends
            </label>
        </div>
        `;
        html = html.replace(/\{\{STOP_ON_COMPLETE\}\}/g, stopOnCompleteHtml);

        // Build elapsed time section
        const elapsedHtml = buildStatus.elapsed ? `
        <div class="info-row">
            <span class="info-label">Elapsed:</span>
            <span>${buildStatus.elapsed}</span>
        </div>
        ` : '';
        html = html.replace(/\{\{BUILD_ELAPSED_TIME\}\}/g, elapsedHtml);

        // Build warning section
        const warningHtml = buildStatus.warning ? `
        <div class="warning">
            <strong>⚠ Warning:</strong> ${this.escapeHtml(buildStatus.warning)}
        </div>
        ` : '';
        html = html.replace(/\{\{BUILD_WARNING\}\}/g, warningHtml);

        // Build errors section - show last error in code window
        const errorsHtml = buildStatus.errors && buildStatus.errors.length > 0 ? `
        <div class="error">
            <strong>Last Error:</strong>
            <div class="error-code-window">
                <pre><code>${buildStatus.errors.map(e => this.escapeHtml(e)).join('\n')}</code></pre>
            </div>
        </div>
        ` : '';
        html = html.replace(/\{\{BUILD_ERRORS\}\}/g, errorsHtml);

        return html;
    }

    private escapeHtml(text: string): string {
        return text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    private async getInstanceStatus(workspacePath: string): Promise<InstanceStatus> {
        try {
            const { stdout } = await execAsync('make instance-status', { cwd: workspacePath });
            const lines = stdout.split('\n');

            const status: InstanceStatus = {
                id: '',
                type: '',
                state: 'unknown',
                ip: undefined,
                healthy: false
            };

            for (const line of lines) {
                if (line.includes('Instance ID:')) {
                    status.id = line.split('Instance ID:')[1]?.trim() || '';
                } else if (line.includes('Instance Type:')) {
                    status.type = line.split('Instance Type:')[1]?.trim() || '';
                } else if (line.includes('State:')) {
                    status.state = line.split('State:')[1]?.trim().toLowerCase() || 'unknown';
                } else if (line.includes('IP:')) {
                    status.ip = line.split('IP:')[1]?.trim();
                }
            }

            return status;
        } catch (error) {
            return { id: '', type: '', state: 'unknown' };
        }
    }

    private async getBuildStatus(workspacePath: string): Promise<BuildStatus> {
        try {
            const { stdout } = await execAsync('make build-status', { cwd: workspacePath });
            const lines = stdout.split('\n');

            const status: BuildStatus = {
                running: stdout.includes('Build session is running'),
                errors: []
            };

            // Extract elapsed time if available (whether running or not)
            const elapsedMatch = stdout.match(/Elapsed time: (.+)/);
            if (elapsedMatch) {
                status.elapsed = elapsedMatch[1];
            }

            // Extract errors if any (when build is not running)
            if (!status.running) {
                const errorSection = stdout.split('=== Recent Build Errors ===');
                if (errorSection.length > 1) {
                    const errorLines = errorSection[1].split('\n')
                        .filter(line => line.trim() && !line.includes('==='))
                        .slice(0, 5);
                    status.errors = errorLines;
                }

                // Extract warning about BitBake lock file
                if (stdout.includes('⚠ Warning: BitBake lock file exists')) {
                    // Extract the full warning block (warning + description + suggestion)
                    const warningSection = stdout.split('⚠ Warning:')[1];
                    if (warningSection) {
                        const warningLines = warningSection.split('\n')
                            .map(line => line.trim())
                            .filter(line => line && !line.startsWith('==='))
                            .slice(0, 3); // Get warning and up to 2 following lines
                        status.warning = warningLines.join(' ');
                    } else {
                        status.warning = 'BitBake lock file exists but no build session is running. Previous build may have been interrupted.';
                    }
                }
            }

            return status;
        } catch (error) {
            return { running: false };
        }
    }

    public dispose() {
        YoctoBuilderPanel.currentPanel = undefined;
        this._panel.dispose();
        while (this._disposables.length) {
            const x = this._disposables.pop();
            if (x) {
                x.dispose();
            }
        }
    }
}

export function deactivate() { }

