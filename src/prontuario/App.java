package prontuario;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import prontuario.dao.AlergiaDAO;
import prontuario.dao.CatalogoDAO;
import prontuario.dao.ConsultaDAO;
import prontuario.dao.ConvenioDAO;
import prontuario.dao.DashboardDAO;
import prontuario.dao.MedicoDAO;
import prontuario.dao.PacienteDAO;
import prontuario.dao.RegrasDAO;
import prontuario.dao.RelatorioDAO;

public class App {
    private static final int PORTA = 8080;
    private static final Path PASTA_WEB = Path.of("web");

    private final PacienteDAO pacientes = new PacienteDAO();
    private final MedicoDAO medicos = new MedicoDAO();
    private final ConvenioDAO convenios = new ConvenioDAO();
    private final RelatorioDAO relatorios = new RelatorioDAO();
    private final DashboardDAO dashboard = new DashboardDAO();
    private final ConsultaDAO consultas = new ConsultaDAO();
    private final CatalogoDAO medicamentos = CatalogoDAO.medicamentos();
    private final CatalogoDAO exames = CatalogoDAO.exames();
    private final AlergiaDAO alergias = new AlergiaDAO();
    private final RegrasDAO regras = new RegrasDAO();

    public static void main(String[] args) throws Exception {
        Database.carregarConfiguracao();
        try (var con = Database.getConnection()) {
            System.out.println("Conectado ao MySQL: " + con.getMetaData().getURL());
        }

        int porta = args.length > 0 ? Integer.parseInt(args[0]) : PORTA;
        HttpServer server = HttpServer.create(new InetSocketAddress(porta), 0);
        App app = new App();
        server.createContext("/api/", app::tratarApi);
        server.createContext("/", App::arquivoEstatico);
        server.start();
        System.out.println("Aplicação rodando em http://localhost:" + porta);
    }

    /**
     * Rotas: /api/{recurso}/{id}/{sub}/{subId}
     * GET com filtros usa a query string (?inicio=...&fim=...); POST/PUT/DELETE usam formulário no corpo.
     */
    private void tratarApi(HttpExchange ex) throws IOException {
        try {
            String[] partes = ex.getRequestURI().getRawPath().replaceAll("/+$", "").split("/");
            String recurso = partes.length > 2 ? partes[2] : "";
            String id = parte(partes, 3);
            String sub = parte(partes, 4);
            String subId = parte(partes, 5);
            String metodo = ex.getRequestMethod();
            Map<String, String> query = lerPares(ex.getRequestURI().getRawQuery());
            Map<String, String> form = lerFormulario(ex);

            Object resposta = switch (recurso) {
                case "dashboard" -> "opcoes".equals(id) ? dashboard.opcoes() : dashboard.carregar(query);
                case "relatorios" -> id == null ? relatorios.listar() : relatorios.executar(id, query);
                case "pacientes" -> "alergias".equals(sub)
                        ? alergias(metodo, id, subId, form)
                        : pacientes(metodo, id, form);
                case "medicos" -> medicos(metodo, id, form);
                case "convenios" -> convenios(metodo, id, form);
                case "consultas" -> consultas(metodo, id, sub, subId, query, form);
                case "medicamentos" -> catalogo(medicamentos, "Medicamento", metodo, id, form);
                case "exames" -> catalogo(exames, "Exame", metodo, id, form);
                case "regras" -> regras(metodo, id, query, form);
                default -> throw new NaoEncontrado("Recurso não encontrado: " + recurso);
            };
            enviarJson(ex, 200, resposta);
        } catch (NaoEncontrado e) {
            enviarJson(ex, 404, Map.of("erro", e.getMessage()));
        } catch (SQLException e) {
            enviarJson(ex, 400, Map.of("erro", mensagemAmigavel(e), "detalhe", e.getMessage()));
        } catch (IllegalArgumentException | java.time.format.DateTimeParseException e) {
            enviarJson(ex, 400, Map.of("erro", e.getMessage()));
        } catch (Exception e) {
            e.printStackTrace();
            enviarJson(ex, 500, Map.of("erro", "Erro interno: " + e.getMessage()));
        }
    }

    private static String parte(String[] partes, int i) {
        return partes.length > i ? URLDecoder.decode(partes[i], StandardCharsets.UTF_8) : null;
    }

    private Object consultas(String metodo, String id, String sub, String subId,
                             Map<String, String> q, Map<String, String> f) throws SQLException {
        if (sub != null) {
            int codigo = Integer.parseInt(id);
            switch (sub + ":" + metodo) {
                case "receita:POST" -> {
                    consultas.criarReceita(codigo, opcional(f, "nome"));
                    return Map.of("mensagem", "Receita criada");
                }
                case "receita:DELETE" -> {
                    verificarAfetadas(consultas.excluirReceita(codigo));
                    return Map.of("mensagem", "Receita excluída (itens removidos em cascata)");
                }
                case "medicamentos:POST" -> {
                    consultas.prescrever(codigo, Integer.parseInt(obrigatorio(f, "codigo_medicamento")));
                    return Map.of("mensagem", "Medicamento incluído na receita");
                }
                case "medicamentos:DELETE" -> {
                    verificarAfetadas(consultas.removerMedicamento(codigo, Integer.parseInt(subId)));
                    return Map.of("mensagem", "Medicamento removido da receita");
                }
                case "exames:POST" -> {
                    consultas.solicitarExame(codigo, Integer.parseInt(obrigatorio(f, "codigo_exame")));
                    return Map.of("mensagem", "Exame solicitado");
                }
                case "exames:DELETE" -> {
                    verificarAfetadas(consultas.removerExame(codigo, Integer.parseInt(subId)));
                    return Map.of("mensagem", "Exame removido");
                }
                default -> throw new NaoEncontrado("Rota não encontrada: " + sub);
            }
        }
        switch (metodo) {
            case "GET":
                if ("opcoes".equals(id)) {
                    return consultas.opcoes();
                }
                if (id != null) {
                    Map<String, Object> d = consultas.detalhar(Integer.parseInt(id));
                    if (d == null) {
                        throw new NaoEncontrado("Consulta não encontrada");
                    }
                    return d;
                }
                return consultas.listar(opcional(q, "inicio"), opcional(q, "fim"));
            case "POST":
                int codigo = consultas.inserir(obrigatorio(f, "cpf_paciente"), obrigatorio(f, "cpf_medico"),
                        opcional(f, "data_consulta"), inteiroOpcional(f, "retorno_de"), opcional(f, "nome_receita"));
                return Map.of("mensagem", "Consulta " + codigo + " cadastrada", "codigo", codigo);
            case "PUT":
                verificarAfetadas(consultas.alterar(Integer.parseInt(id), obrigatorio(f, "cpf_paciente"),
                        obrigatorio(f, "cpf_medico"), opcional(f, "data_consulta")));
                return Map.of("mensagem", "Consulta alterada");
            case "DELETE":
                verificarAfetadas(consultas.excluir(Integer.parseInt(id)));
                return Map.of("mensagem", "Consulta excluída (receita, itens, exames e retornos em cascata)");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    private Object catalogo(CatalogoDAO dao, String nome, String metodo, String codigo, Map<String, String> f)
            throws SQLException {
        switch (metodo) {
            case "GET":
                return dao.listar();
            case "POST":
                dao.inserir(obrigatorio(f, "nome"));
                return Map.of("mensagem", nome + " cadastrado");
            case "PUT":
                verificarAfetadas(dao.alterar(Integer.parseInt(codigo),
                        Integer.parseInt(obrigatorio(f, "codigo")), obrigatorio(f, "nome")));
                return Map.of("mensagem", nome + " alterado");
            case "DELETE":
                verificarAfetadas(dao.excluir(Integer.parseInt(codigo)));
                return Map.of("mensagem", nome + " excluído");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    private Object alergias(String metodo, String cpf, String alergia, Map<String, String> f) throws SQLException {
        switch (metodo) {
            case "GET":
                return alergias.listar(cpf);
            case "POST":
                alergias.inserir(cpf, obrigatorio(f, "alergia"));
                return Map.of("mensagem", "Alergia registrada");
            case "PUT":
                verificarAfetadas(alergias.alterar(cpf, alergia, obrigatorio(f, "alergia")));
                return Map.of("mensagem", "Alergia alterada");
            case "DELETE":
                verificarAfetadas(alergias.excluir(cpf, alergia));
                return Map.of("mensagem", "Alergia removida");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    /** Etapa 05: funções, procedimentos e triggers. */
    private Object regras(String metodo, String acao, Map<String, String> q, Map<String, String> f)
            throws SQLException {
        switch (metodo + ":" + acao) {
            case "GET:objetos":
                return regras.objetos();
            case "GET:polifarmacia":
                return regras.polifarmacia(opcional(q, "classe"));
            case "GET:alergia":
                return regras.verificarAlergia(obrigatorio(q, "cpf"), Integer.parseInt(obrigatorio(q, "medicamento")));
            case "GET:conflitos":
                return regras.conflitosGravados();
            case "POST:convenio":
                return regras.atualizarConvenio(obrigatorio(f, "cpf"), inteiroOpcional(f, "codigo_convenio"));
            case "GET:sem-consulta":
                return regras.pacientesSemConsulta();
            case "POST:agendar":
                return regras.agendar("true".equals(f.get("confirmar")));
            case "GET:consultas-com-receita":
                return regras.consultasComReceita();
            case "POST:testar-trigger":
                return regras.testarTriggerAlergia(Integer.parseInt(obrigatorio(f, "codigo_consulta")),
                        Integer.parseInt(obrigatorio(f, "codigo_medicamento")));
            case "GET:log":
                return regras.log();
            default:
                throw new NaoEncontrado("Ação não encontrada: " + acao);
        }
    }

    private Object pacientes(String metodo, String cpf, Map<String, String> f) throws SQLException {
        switch (metodo) {
            case "GET":
                return pacientes.listar();
            case "POST":
                pacientes.inserir(obrigatorio(f, "cpf"), obrigatorio(f, "nome"), obrigatorio(f, "cep"),
                        opcional(f, "numero_apto"), inteiroOpcional(f, "codigo_convenio"), opcional(f, "telefone"));
                return Map.of("mensagem", "Paciente cadastrado");
            case "PUT":
                verificarAfetadas(pacientes.alterar(cpf, obrigatorio(f, "cpf"), obrigatorio(f, "nome"),
                        obrigatorio(f, "cep"), opcional(f, "numero_apto"), inteiroOpcional(f, "codigo_convenio")));
                return Map.of("mensagem", "Paciente alterado");
            case "DELETE":
                verificarAfetadas(pacientes.excluir(cpf));
                return Map.of("mensagem", "Paciente excluído");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    private Object medicos(String metodo, String cpf, Map<String, String> f) throws SQLException {
        switch (metodo) {
            case "GET":
                return medicos.listar();
            case "POST":
                medicos.inserir(obrigatorio(f, "cpf"), obrigatorio(f, "nome"), obrigatorio(f, "cep"),
                        opcional(f, "numero_apto"), obrigatorio(f, "crm"), opcional(f, "especialidade"));
                return Map.of("mensagem", "Médico cadastrado");
            case "PUT":
                verificarAfetadas(medicos.alterar(cpf, obrigatorio(f, "cpf"), obrigatorio(f, "nome"),
                        obrigatorio(f, "cep"), opcional(f, "numero_apto"), obrigatorio(f, "crm"),
                        opcional(f, "especialidade")));
                return Map.of("mensagem", "Médico alterado");
            case "DELETE":
                verificarAfetadas(medicos.excluir(cpf));
                return Map.of("mensagem", "Médico excluído");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    private Object convenios(String metodo, String codigo, Map<String, String> f) throws SQLException {
        switch (metodo) {
            case "GET":
                return convenios.listar();
            case "POST":
                convenios.inserir(obrigatorio(f, "nome"));
                return Map.of("mensagem", "Convênio cadastrado");
            case "PUT":
                verificarAfetadas(convenios.alterar(Integer.parseInt(codigo),
                        Integer.parseInt(obrigatorio(f, "codigo")), obrigatorio(f, "nome")));
                return Map.of("mensagem", "Convênio alterado");
            case "DELETE":
                verificarAfetadas(convenios.excluir(Integer.parseInt(codigo)));
                return Map.of("mensagem", "Convênio excluído (pacientes dele agora são particulares)");
            default:
                throw new IllegalArgumentException("Método não suportado: " + metodo);
        }
    }

    private static String mensagemAmigavel(SQLException e) {
        return switch (e.getErrorCode()) {
            case 1062 -> "Registro duplicado: já existe um cadastro com esse valor único (CPF, CRM, nome...).";
            case 1451 -> "Não é possível excluir/alterar: existem registros que dependem deste (ex.: consultas ou receitas que o usam).";
            case 1452 -> "Referência inválida: o registro relacionado não existe.";
            case 3819 -> "Valor inválido: violou a restrição " + restricao(e.getMessage()) + ".";
            case 1406 -> "Valor maior do que o tamanho permitido para o campo.";
            case 1048 -> "Campo obrigatório não informado: " + e.getMessage();
            case 1292 -> "Valor inválido (data ou número): " + e.getMessage();
            case 1644 -> e.getMessage();
            case 0 -> "Não foi possível conectar ao banco de dados: " + e.getMessage();
            default -> "Erro no banco de dados: " + e.getMessage();
        };
    }

    private static String restricao(String mensagem) {
        int i = mensagem.indexOf('\'');
        int j = mensagem.indexOf('\'', i + 1);
        return i >= 0 && j > i ? mensagem.substring(i + 1, j) : "CHECK";
    }

    private static void verificarAfetadas(int linhas) {
        if (linhas == 0) {
            throw new NaoEncontrado("Registro não encontrado");
        }
    }

    private static String obrigatorio(Map<String, String> f, String campo) {
        String valor = opcional(f, campo);
        if (valor == null) {
            throw new IllegalArgumentException("O campo '" + campo + "' é obrigatório");
        }
        return valor;
    }

    private static String opcional(Map<String, String> f, String campo) {
        String valor = f.get(campo);
        return valor == null || valor.isBlank() ? null : valor.trim();
    }

    private static Integer inteiroOpcional(Map<String, String> f, String campo) {
        String valor = opcional(f, campo);
        return valor == null ? null : Integer.valueOf(valor);
    }

    private static Map<String, String> lerFormulario(HttpExchange ex) throws IOException {
        return lerPares(new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
    }

    private static Map<String, String> lerPares(String corpo) {
        Map<String, String> campos = new HashMap<>();
        if (corpo == null) {
            return campos;
        }
        for (String par : corpo.split("&")) {
            if (par.isEmpty()) {
                continue;
            }
            String[] kv = par.split("=", 2);
            campos.put(URLDecoder.decode(kv[0], StandardCharsets.UTF_8),
                    kv.length > 1 ? URLDecoder.decode(kv[1], StandardCharsets.UTF_8) : "");
        }
        return campos;
    }

    private static void enviarJson(HttpExchange ex, int status, Object corpo) throws IOException {
        enviar(ex, status, "application/json; charset=utf-8", Json.escrever(corpo).getBytes(StandardCharsets.UTF_8));
    }

    private static void enviar(HttpExchange ex, int status, String tipo, byte[] bytes) throws IOException {
        ex.getResponseHeaders().set("Content-Type", tipo);
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = ex.getResponseBody()) {
            out.write(bytes);
        }
    }

    private static void arquivoEstatico(HttpExchange ex) throws IOException {
        String caminho = ex.getRequestURI().getPath();
        if (caminho.equals("/")) {
            caminho = "/index.html";
        }
        Path arquivo = PASTA_WEB.resolve(caminho.substring(1)).normalize();
        if (!arquivo.startsWith(PASTA_WEB) || !Files.isRegularFile(arquivo)) {
            enviar(ex, 404, "text/plain; charset=utf-8", "Não encontrado".getBytes(StandardCharsets.UTF_8));
            return;
        }
        enviar(ex, 200, tipoConteudo(arquivo.toString()), Files.readAllBytes(arquivo));
    }

    private static String tipoConteudo(String nome) {
        for (var e : List.of(
                Map.entry(".html", "text/html; charset=utf-8"),
                Map.entry(".css", "text/css; charset=utf-8"),
                Map.entry(".js", "text/javascript; charset=utf-8"),
                Map.entry(".svg", "image/svg+xml"),
                Map.entry(".png", "image/png"))) {
            if (nome.endsWith(e.getKey())) {
                return e.getValue();
            }
        }
        return "application/octet-stream";
    }

    private static class NaoEncontrado extends RuntimeException {
        NaoEncontrado(String mensagem) {
            super(mensagem);
        }
    }
}
