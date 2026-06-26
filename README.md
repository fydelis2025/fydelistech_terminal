# 🚀 x86_64 PTY Shell em Assembly Puro

Este projeto documenta a criação e inicialização de um Pseudo-Terminal (PTY) no Linux utilizando apenas Assembly x86_64 nativo e chamadas de sistema do Kernel (`syscall`).

## 🧠 Como o Fluxo Funciona (Baixíssimo Nível):
1. **Mestre PTY:** Abre-se `/dev/ptmx` para gerar um descritor mestre.
2. **Destravamento:** Chamas de `ioctl` com `TIOCSPTLCK` liberam o lado escravo.
3. **Identificação:** O comando `TIOCGPTN` descobre o ID numérico do escravo gerado pelo kernel.
4. **Isolamento (`Fork`):** - O processo **Pai** gerencia a multiplexação (`sys_select`) repassando o que o usuário digita para o mestre PTY, e o que o PTY responde de volta para a tela.
   - O processo **Filho** cria uma nova sessão (`setsid`), abre o caminho `/dev/pts/X` (PTY Escravo), clona os descritores padrões (`stdin`, `stdout`, `stderr`) para ele com `dup2` e substitui o processo pelo interpretador de comandos através do `sys_execve`.

*Nota de documentação:* O aviso clássico do `-bash` (`ioctl inapropriado para dispositivo`) ocorre porque o terminal hospedeiro original (de onde o binário foi chamado) permanece em modo Canônico, fazendo com que o subsistema de Job Control do Bash não consiga sincronizar os sinais de controle com o PTY interno sem que o processo Pai altere o terminal original para Modo RAW.
